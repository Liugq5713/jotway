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
<p class="status-label">发行状态 · 尚未发布</p><h2 id="release-title">公开下载，准备中。</h2>
<p>目前没有可供公开下载的发行包，因此这里暂不提供下载按钮。版本、构建号、系统要求、架构、大小、SHA-256、签名、公证状态和发布日期，会在真实产物发布后同步显示。</p>
<a class="text-link" href="https://github.com/Liugq5713/jotway/releases">查看 GitHub 发行记录 ↗</a></section>'''
    local = record['status'] == 'local'
    sign = {'ad-hoc': 'ad-hoc 签名', 'developer-id': 'Developer ID 签名', 'unsigned': '未签名'}[record['codeSigning']]
    fields = [('版本', record['version']), ('构建号', record['build']),
              ('最低 macOS', record['minimumMacOS']), ('CPU 架构', record['architecture']),
              ('文件', record['file']), ('文件大小', f"{record['bytes'] / 1024 / 1024:.2f} MiB · {record['bytes']:,} bytes"),
              ('签名', sign), ('Apple 公证', '已公证' if record['notarized'] else '未公证'),
              ('打包日期 (UTC)' if local else '发布日期 (UTC)', record['releaseDate'])]
    facts = ''.join(f'<div><dt>{escape(name)}</dt><dd>{escape(str(value))}</dd></div>' for name, value in fields)
    facts += f'''<div class="wide"><dt>SHA-256</dt><dd><code id="checksum">{record['sha256']}</code><br>
<button class="checksum-copy" id="copy-checksum" type="button">复制校验值</button><span id="copy-status" role="status"></span></dd></div>
<div class="wide"><dt>下载地址</dt><dd><a href="{escape(record['downloadURL'], quote=True)}">{escape(record['downloadURL'])}</a></dd></div>'''
    safety = f"此发行包为{sign}，{'已' if record['notarized'] else '尚未'}经过 Apple notarization。"
    release_link = '' if local else f'<a href="{escape(record["releaseURL"], quote=True)}">在 GitHub 查看此次发行 ↗</a>'
    return f'''<section class="release-card" aria-labelledby="release-title"><p class="status-label">{'本地验证包 · 未公开发布' if local else '已发布'}</p>
<h2 id="release-title">Jotway {escape(record['version'])}</h2><dl class="release-facts">{facts}</dl>
<a class="button primary download-button" href="{escape(record['downloadURL'], quote=True)}">{'下载本地验证包' if local else '下载 Jotway'} · DMG ↗</a>
<p class="signing-note">{safety}</p><div class="document-section"><h3>发行说明</h3><p class="release-notes">{escape(record['notes'])}</p>
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
    for name in ('launcher-light.png', 'launcher-dark.png', 'README-flow.png'):
        shutil.copyfile(ROOT / 'Resources/Screenshots' / name, output / 'assets' / name)
    shutil.copyfile(ROOT / 'Resources/Icons/AppIcon.png', output / 'assets/AppIcon.png')
    (output / 'release.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n')
    layout = (SITE / 'src/layout.html').read_text()
    published = metadata['status'] == 'published'
    common = {'home_cta': '下载 Jotway' if published else '查看下载状态',
              'release_summary': f"{metadata['version']} · macOS {metadata['minimumMacOS']}+ · {metadata['architecture']}" if published else ('本地验证包 · 未公开发布' if artifact else '公开发行包尚未发布 · 可从源码构建'),
              'release_content': release_content(metadata),
              'signing_guidance': ('当前打包流程使用 ad-hoc 签名，尚未经过 Apple notarization。' if metadata['status'] == 'unpublished'
                                   else '此发行包的签名与公证结果见上方产物信息。')
                                  + '首次打开时，macOS 可能要求你在“系统设置 → 隐私与安全性”中允许打开。请先确认文件来源与校验值。'}
    routes = [('home', '', 'Jotway — 打一句话，送到该去的地方。', '用快捷键唤起，写下一句话，确认目标，再按 Enter。原生 macOS 启动器 Jotway，把内容交给日常工具。'),
              ('download', 'download', '下载 Jotway — 发行与安装', '查看真实发行包、校验值、签名和公证状态，以及 Jotway 安装方式。'),
              ('privacy', 'privacy', 'Jotway — 隐私与数据流', '了解 Jotway 草稿、可选 AI 请求、本地完整正文反馈样本，以及保留和清除边界。')]
    for source, route, title, description in routes:
        content = (SITE / 'src' / f'{source}.html').read_text()
        content = re.sub(r'\{\{(\w+)\}\}', lambda match: common[match[1]], content)
        values = {'content': content, 'title': title, 'description': description,
                  'asset_revision': hashlib.sha256((SITE / 'src/site.css').read_bytes() + (SITE / 'src/site.js').read_bytes()).hexdigest()[:12],
                  'privacy_current': 'aria-current="page"' if route == 'privacy' else '',
                  'download_current': 'aria-current="page"' if route == 'download' else ''}
        html = re.sub(r'\{\{(\w+)\}\}', lambda match: values[match[1]], layout)
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
