#!/usr/bin/env python3
"""Build the three-page site using only Python's standard library."""
import argparse
from html import escape
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import shutil
import sys
from urllib.parse import unquote, urlsplit
from release_metadata import local_preview, validate

ROOT = Path(__file__).resolve().parents[2]
SITE = ROOT / 'website'


def release_content(record):
    if record['status'] == 'unpublished':
        return '''<section class="unpublished" aria-labelledby="release-title">
<p class="status-label">Release status · Not yet published</p><h2 id="release-title">A public download is on its way.</h2>
<p>There is no public release to download yet. Once a verified artifact is published, this page will show its version, build, macOS requirement, architecture, size, SHA-256, signing, notarization, and release date.</p>
<a class="text-link" href="https://github.com/Liugq5713/jotway/releases">View GitHub releases ↗</a></section>'''
    local = record['status'] == 'local'
    sign = {'ad-hoc': 'Ad-hoc signing', 'developer-id': 'Developer ID signing', 'unsigned': 'Unsigned'}[record['codeSigning']]
    fields = [('Version', record['version']), ('Build', record['build']),
              ('Minimum macOS', record['minimumMacOS']), ('CPU architecture', record['architecture']),
              ('File', record['file']), ('File size', f"{record['bytes'] / 1024 / 1024:.2f} MiB · {record['bytes']:,} bytes"),
              ('Signing', sign), ('Apple notarization', 'Notarized' if record['notarized'] else 'Not notarized'),
              ('Packaged at (UTC)' if local else 'Released at (UTC)', record['releaseDate'])]
    facts = ''.join(f'<div><dt>{escape(name)}</dt><dd>{escape(str(value))}</dd></div>' for name, value in fields)
    facts += f'''<div class="wide"><dt>SHA-256</dt><dd><code id="checksum">{record['sha256']}</code><br>
<button class="checksum-copy" id="copy-checksum" type="button">Copy checksum</button><span id="copy-status" role="status"></span></dd></div>
<div class="wide"><dt>Download URL</dt><dd><a href="{escape(record['downloadURL'], quote=True)}">{escape(record['downloadURL'])}</a></dd></div>'''
    safety = f"Signing: {sign}. {'Notarized by Apple.' if record['notarized'] else 'Not notarized by Apple.'}"
    notes = escape(record['notes'])
    if re.search(r'[\u3400-\u9fff]', record['notes']):
        notes = 'Read the original release notes in the <a href="/release.json">release metadata</a>.'
    release_link = '' if local else f'<a href="{escape(record["releaseURL"], quote=True)}">View this release on GitHub ↗</a>'
    return f'''<section class="release-card" aria-labelledby="release-title"><p class="status-label">{'Local preview · Not publicly released' if local else 'Published'}</p>
<h2 id="release-title">Jotway {escape(record['version'])}</h2><dl class="release-facts">{facts}</dl>
<a class="button primary download-button" href="{escape(record['downloadURL'], quote=True)}">{'Download local preview' if local else 'Download Jotway'} · DMG ↗</a>
<p class="signing-note">{safety}</p><div class="document-section"><h3>Release notes</h3><p class="release-notes">{notes}</p>
{release_link}</div></section>'''


class References(HTMLParser):
    def __init__(self):
        super().__init__()
        self.references = []
        self.ids = set()
    def handle_starttag(self, tag, attributes):
        attrs = dict(attributes)
        if attrs.get('id'):
            if attrs['id'] in self.ids:
                raise ValueError(f'Duplicate HTML ID: {attrs["id"]}')
            self.ids.add(attrs['id'])
        for name in ('href', 'src'):
            if attrs.get(name):
                self.references.append(attrs[name])


def verify_links(output):
    pages = {}
    for path in output.rglob('*.html'):
        parser = References()
        parser.feed(path.read_text())
        pages[path.resolve()] = parser
    for path, page in pages.items():
        for value in page.references:
            ref = urlsplit(value)
            if ref.scheme or ref.netloc:
                continue
            target = (output / unquote(ref.path).lstrip('/')) if ref.path.startswith('/') else (path.parent / unquote(ref.path))
            if not ref.path:
                target = path
            if target.is_dir():
                target /= 'index.html'
            if not target.is_file():
                raise ValueError(f'{path.relative_to(output)}: broken reference {value}')
            if ref.fragment and target.resolve() in pages and ref.fragment not in pages[target.resolve()].ids:
                raise ValueError(f'{path.relative_to(output)}: missing fragment {value}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    inputs = parser.add_mutually_exclusive_group()
    inputs.add_argument('--metadata', type=Path, default=SITE / 'release.json')
    inputs.add_argument('--local-release', type=Path, help='Preview a verified local DMG; never marks it published')
    # Output is fixed to avoid deleting arbitrary user directories during a rebuild.
    args = parser.parse_args()
    artifact = None
    if args.local_release:
        metadata, artifact = local_preview(args.local_release)
    else:
        metadata = json.loads(args.metadata.read_text())
        validate(metadata)
    output = SITE / 'dist'
    if output.is_symlink():
        raise ValueError('Refusing to replace symlinked website/dist.')
    if output.exists():
        shutil.rmtree(output)
    (output / 'assets').mkdir(parents=True)
    if artifact:
        (output / 'downloads').mkdir()
        shutil.copyfile(artifact, output / 'downloads' / artifact.name)
    for name in ('site.css', 'site.js'):
        shutil.copyfile(SITE / 'src' / name, output / 'assets' / name)
    shutil.copyfile(ROOT / 'Resources/Icons/AppIcon.png', output / 'assets/AppIcon.png')
    (output / 'release.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n')
    layout = (SITE / 'src/layout.html').read_text()
    published = metadata['status'] == 'published'
    common = {'home_cta': 'Download Jotway' if published else 'Check availability',
              'release_summary': f"{metadata['version']} · macOS {metadata['minimumMacOS']}+ · {metadata['architecture']}" if published else ('Local preview · Not publicly released' if artifact else 'No public release yet · Source builds available'),
              'release_content': release_content(metadata),
              'signing_guidance': ('The current packaging process uses ad-hoc signing without Apple notarization. ' if metadata['status'] == 'unpublished'
                                   else 'See the artifact details above for signing and notarization status. ')
                                  + 'On first launch, macOS may ask you to allow the app in System Settings → Privacy & Security. Verify the source and checksum first.'}
    routes = [('home', '', 'Jotway — One thought. The right place.', 'Open Jotway, type a thought, check the Action, and press Enter. A native macOS launcher for your everyday tools.'),
              ('download', 'download', 'Download Jotway — Releases and installation', 'Verified release details, checksums, signing and notarization status, and installation instructions for Jotway.'),
              ('privacy', 'privacy', 'Jotway — Privacy and data flow', 'Understand Jotway drafts, optional AI requests, full-text local feedback, retention, and available clearing controls.')]
    for source, route, title, description in routes:
        content = (SITE / 'src' / f'{source}.html').read_text()
        content = re.sub(r'\{\{(\w+)\}\}', lambda match: common[match[1]], content)
        site_prefix = './' if not route else '../'
        values = {'content': content, 'title': title, 'description': description,
                  'site_prefix': site_prefix,
                  'asset_revision': hashlib.sha256((SITE / 'src/site.css').read_bytes() + (SITE / 'src/site.js').read_bytes()).hexdigest()[:12],
                  'privacy_current': 'aria-current="page"' if route == 'privacy' else '',
                  'download_current': 'aria-current="page"' if route == 'download' else ''}
        html = re.sub(r'\{\{(\w+)\}\}', lambda match: values[match[1]], layout)
        if re.search(r'[\u3400-\u9fff]', html):
            raise ValueError(f'{route or "home"}: non-English website copy found.')
        html = html.replace('href="/', f'href="{site_prefix}').replace('src="/', f'src="{site_prefix}')
        destination = output / route / 'index.html'
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(html)
    verify_links(output)
    print(f'Built /, /download/, /privacy/ ({metadata["status"]}); local links and fragments verified.\n{output}')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError, TypeError) as error:
        sys.exit(f'Site build failed: {error}')
