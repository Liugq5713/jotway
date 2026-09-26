#!/usr/bin/env python3
"""Verify a stable GitHub release's public artifact and export site metadata.

Read-only network access: this command never publishes a release or deploys a site.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
from urllib.request import Request, urlopen
from release_metadata import sha256, validate


def uploaded_asset(release, name):
    assets = [asset for asset in release['assets'] if asset['name'] == name and asset['state'] == 'uploaded']
    if len(assets) != 1:
        raise ValueError(f'The published release must contain exactly one uploaded {name}.')
    return assets[0]


def public_request(url):
    return Request(url, headers={'User-Agent': 'Jotway-release-verifier'})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--release', type=Path, help='Local release.json and adjacent DMG; otherwise use the public release.json asset')
    parser.add_argument('--repository', default='Liugq5713/jotway')
    parser.add_argument('--tag', help='Stable vMAJOR.MINOR.PATCH tag; defaults to GitHub latest release')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', args.repository):
        raise ValueError('Invalid repository.')
    if args.tag and not re.fullmatch(r'v\d+\.\d+\.\d+', args.tag):
        raise ValueError('Tag must be vMAJOR.MINOR.PATCH.')
    endpoint = f'tags/{args.tag}' if args.tag else 'latest'
    response = subprocess.check_output(['gh', 'api', f'repos/{args.repository}/releases/{endpoint}'], text=True)
    release = json.loads(response)
    if release['draft'] or release['prerelease'] or not release['published_at']:
        raise ValueError('Only a published, stable release may become the site download.')
    tag = release['tag_name']
    if not re.fullmatch(r'v\d+\.\d+\.\d+', tag) or (args.tag and tag != args.tag):
        raise ValueError('The release must have a matching vMAJOR.MINOR.PATCH tag.')
    if args.release:
        record = json.loads(args.release.read_text())
    else:
        metadata_asset = uploaded_asset(release, 'release.json')
        with urlopen(public_request(metadata_asset['browser_download_url']), timeout=90) as remote:
            raw = remote.read(1024 * 1024 + 1)
        if len(raw) > 1024 * 1024 or len(raw) != metadata_asset['size']:
            raise ValueError('Public release.json size is invalid.')
        digest = metadata_asset.get('digest')
        if digest and digest != 'sha256:' + hashlib.sha256(raw).hexdigest():
            raise ValueError('Public release.json digest does not match GitHub.')
        record = json.loads(raw)
    if record['version'] != tag[1:]:
        raise ValueError('Tag does not match the artifact version.')
    if Path(record['file']).name != record['file']:
        raise ValueError('Artifact filename must not contain a directory.')
    asset = uploaded_asset(release, record['file'])
    exported = {key: record[key] for key in ('version', 'build', 'minimumMacOS', 'architecture', 'file',
                                             'bytes', 'sha256', 'codeSigning', 'notarized', 'notes')}
    exported.update(schemaVersion=1, status='published', releaseDate=release['published_at'],
                    downloadURL=asset['browser_download_url'], releaseURL=release['html_url'])
    validate(exported)
    if args.release:
        artifact = args.release.parent / record['file']
        if artifact.stat().st_size != record['bytes'] or sha256(artifact) != record['sha256']:
            raise ValueError('Local artifact size/checksum does not match release.json.')
    if asset['size'] != record['bytes']:
        raise ValueError('The published artifact size does not match release.json.')
    digest = asset.get('digest')
    if digest and digest != 'sha256:' + record['sha256']:
        raise ValueError('GitHub artifact digest does not match the local artifact.')
    # Read without auth to prove that users can download the recorded bytes.
    request = public_request(asset['browser_download_url'])
    remote_digest, size = hashlib.sha256(), 0
    with urlopen(request, timeout=90) as remote:
        for chunk in iter(lambda: remote.read(1024 * 1024), b''):
            size += len(chunk)
            if size > record['bytes']:
                raise ValueError('Remote artifact is larger than the local artifact.')
            remote_digest.update(chunk)
    if size != record['bytes'] or remote_digest.hexdigest() != record['sha256']:
        raise ValueError('Public download bytes do not match the local artifact.')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(exported, ensure_ascii=False, indent=2) + '\n')
    print(f'Public artifact verified ({tag}); wrote {args.output}')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError) as error:
        sys.exit(f'Release metadata failed: {error}')
