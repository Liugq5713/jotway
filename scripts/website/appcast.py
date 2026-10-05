"""Validate the public Sparkle feed against the verified release artifact."""
import base64
import binascii
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
SPARKLE = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
MAX_BYTES = 1024 * 1024


def empty_feed():
    return (b'<?xml version="1.0" encoding="utf-8"?>\n'
            b'<rss version="2.0"><channel><title>Jotway updates</title>'
            b'<link>https://liugq5713.github.io/jotway/</link>'
            b'<description>Jotway application updates</description></channel></rss>\n')


def validate_feed(raw, metadata):
    if len(raw) > MAX_BYTES or b'<!DOCTYPE' in raw.upper() or b'<!ENTITY' in raw.upper():
        raise ValueError('Appcast is too large or contains unsupported XML declarations.')
    try:
        root = ET.fromstring(raw)
    except ET.ParseError as error:
        raise ValueError('Appcast is not valid XML.') from error
    channels = root.findall('channel')
    if root.tag != 'rss' or root.get('version') != '2.0' or len(channels) != 1:
        raise ValueError('Appcast must be an RSS 2.0 feed with one channel.')
    items = channels[0].findall('item')
    online = metadata.get('status') == 'published' and metadata.get('updatesEnabled', False)
    if not online:
        if root.findall('.//item') or root.findall('.//enclosure'):
            raise ValueError('Releases without online updates must have an empty appcast.')
        return None
    if len(items) != 1 or root.findall('.//item') != items:
        raise ValueError('Appcast must contain exactly the published release.')
    item = items[0]
    expected = {'version': str(metadata['build']), 'shortVersionString': metadata['version'],
                'minimumSystemVersion': metadata['minimumMacOS'], 'hardwareRequirements': 'arm64'}
    if metadata['architecture'] != 'arm64':
        raise ValueError('Online updates currently require an arm64 artifact.')
    for field, value in expected.items():
        elements = item.findall(SPARKLE + field)
        if len(elements) != 1 or elements[0].text != value:
            raise ValueError(f'Appcast {field} does not match the published release.')
    descriptions = item.findall('description')
    if (len(descriptions) != 1 or descriptions[0].get(SPARKLE + 'format') != 'plain-text'
            or descriptions[0].text != metadata['notes']):
        raise ValueError('Appcast release notes do not match the published release.')
    enclosures = item.findall('enclosure')
    if len(enclosures) != 1 or root.findall('.//enclosure') != enclosures:
        raise ValueError('Appcast must contain exactly one full update enclosure.')
    enclosure = enclosures[0]
    if (enclosure.get('url') != metadata['downloadURL']
            or enclosure.get('length') != str(metadata['bytes'])
            or enclosure.get('type') != 'application/octet-stream'):
        raise ValueError('Appcast download does not match the published artifact.')
    for field, value in expected.items():
        if enclosure.get(SPARKLE + field, value) != value:
            raise ValueError(f'Conflicting appcast enclosure {field}.')
    if enclosure.get(SPARKLE + 'deltaFrom') is not None:
        raise ValueError('Appcast enclosure must be a full update.')
    signature = enclosure.get(SPARKLE + 'edSignature', '')
    decode_key(signature, 64, 'Appcast Ed25519 signature')
    return signature


def decode_key(value, size, label):
    try:
        decoded = base64.b64decode(value, validate=True)
    except (binascii.Error, ValueError, TypeError):
        raise ValueError(f'{label} is invalid.') from None
    if len(decoded) != size:
        raise ValueError(f'{label} must contain {size} bytes.')
    return decoded


def openssl_command():
    candidates = ['/opt/homebrew/opt/openssl@3/bin/openssl',
                  '/usr/local/opt/openssl@3/bin/openssl', shutil.which('openssl')]
    for candidate in candidates:
        if not candidate or not Path(candidate).is_file():
            continue
        result = subprocess.run([candidate, 'version'], capture_output=True, text=True)
        match = re.match(r'OpenSSL (\d+)\.', result.stdout)
        if result.returncode == 0 and match and int(match[1]) >= 3:
            return candidate
    raise ValueError('OpenSSL 3 is required to verify Sparkle Ed25519 signatures.')


def verify_signature(artifact, signature):
    # Trust the same pinned key as the application, never a key from release assets.
    with (ROOT / 'Resources/Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    public_key = decode_key(info.get('SUPublicEDKey'), 32, 'Application update public key')
    signature_bytes = decode_key(signature, 64, 'Appcast Ed25519 signature')
    openssl = openssl_command()
    with tempfile.TemporaryDirectory(prefix='jotway-update-signature-') as directory:
        public_path, signature_path = Path(directory) / 'public.der', Path(directory) / 'signature'
        # RFC 8410 SubjectPublicKeyInfo wrapping the raw Ed25519 public key.
        public_path.write_bytes(bytes.fromhex('302a300506032b6570032100') + public_key)
        signature_path.write_bytes(signature_bytes)
        result = subprocess.run([openssl, 'pkeyutl', '-verify', '-rawin', '-pubin', '-keyform', 'DER',
                                 '-inkey', str(public_path), '-sigfile', str(signature_path),
                                 '-in', str(artifact)], capture_output=True)
    if result.returncode:
        raise ValueError('Public DMG signature does not match the application update public key.')
