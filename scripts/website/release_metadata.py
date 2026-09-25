"""Shared release contract for the static site and artifact verification."""
from datetime import datetime
import hashlib
from pathlib import Path
import re
from urllib.parse import urlsplit


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def validate(metadata, *, allow_local=False):
    if metadata.get('schemaVersion') != 1:
        raise ValueError('Unsupported release metadata schema.')
    if metadata.get('status') == 'unpublished':
        if set(metadata) != {'schemaVersion', 'status'}:
            raise ValueError('An unpublished site record must not advertise an artifact.')
        return
    local = allow_local and metadata.get('status') == 'local'
    if metadata.get('status') != 'published' and not local:
        raise ValueError('Release status must be unpublished or published.')
    for key in ('version', 'build', 'minimumMacOS', 'architecture', 'file', 'bytes', 'sha256',
                'codeSigning', 'notarized', 'releaseDate', 'downloadURL', 'notes'):
        if key not in metadata:
            raise ValueError(f'Missing release field: {key}')
    if not re.fullmatch(r'\d+\.\d+\.\d+', metadata['version']):
        raise ValueError('Invalid release version.')
    if not isinstance(metadata['build'], int) or isinstance(metadata['build'], bool) or metadata['build'] < 1:
        raise ValueError('Invalid build number.')
    if not re.fullmatch(r'\d+(?:\.\d+){1,2}', metadata['minimumMacOS']):
        raise ValueError('Invalid minimum macOS version.')
    if metadata['architecture'] not in ('arm64', 'x86_64', 'arm64 x86_64', 'x86_64 arm64'):
        raise ValueError('Unknown architecture.')
    if not re.fullmatch(r'Jotway-[a-zA-Z0-9._-]+\.dmg', metadata['file']):
        raise ValueError('Invalid DMG filename.')
    if not isinstance(metadata['bytes'], int) or isinstance(metadata['bytes'], bool) or metadata['bytes'] <= 0:
        raise ValueError('Invalid artifact size.')
    if not re.fullmatch('[a-f0-9]{64}', metadata['sha256']):
        raise ValueError('Invalid SHA-256.')
    if metadata['codeSigning'] not in ('ad-hoc', 'developer-id', 'unsigned') or type(metadata['notarized']) is not bool:
        raise ValueError('Unknown signing/notarization state.')
    date = datetime.fromisoformat(metadata['releaseDate'].replace('Z', '+00:00'))
    if date.tzinfo is None:
        raise ValueError('Release date must include a timezone.')
    if local:
        if metadata['downloadURL'] != '/downloads/' + metadata['file']:
            raise ValueError('Local download must refer to the verified artifact.')
    for key in (() if local else ('downloadURL', 'releaseURL')):
        url = urlsplit(metadata[key])
        if url.scheme != 'https' or not url.netloc or url.username or url.password or url.fragment:
            raise ValueError(f'{key} must be a public HTTPS URL.')
    if not isinstance(metadata['notes'], str):
        raise ValueError('Release notes must be text.')


def local_preview(record_path):
    import json
    record = json.loads(record_path.read_text())
    if Path(record['file']).name != record['file']:
        raise ValueError('Artifact filename must not contain a directory.')
    artifact = record_path.parent / record['file']
    if artifact.stat().st_size != record['bytes'] or sha256(artifact) != record['sha256']:
        raise ValueError('Local artifact size/checksum does not match release.json.')
    result = {key: record[key] for key in ('version', 'build', 'minimumMacOS', 'architecture', 'file',
                                          'bytes', 'sha256', 'codeSigning', 'notarized', 'notes')}
    result.update(schemaVersion=1, status='local', releaseDate=record['createdAt'],
                  downloadURL='/downloads/' + record['file'])
    validate(result, allow_local=True)
    return result, artifact
