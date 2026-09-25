#!/bin/bash
# 仅修改图标设计时运行；日常 build-app.sh 使用已导出的图标，无额外依赖。
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v rsvg-convert >/dev/null 2>&1; then
    echo "缺少 rsvg-convert；请安装 librsvg 后再导出图标。" >&2
    exit 1
fi

ICON_WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/jotway-icons.XXXXXX")"
trap 'rm -rf "$ICON_WORK_DIR"' EXIT
ICONSET="$ICON_WORK_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"

for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Resources/Icons/AppIcon.png \
        --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z "$((size * 2))" "$((size * 2))" Resources/Icons/AppIcon.png \
        --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
rsvg-convert -f pdf -w 18pt -h 18pt Resources/Icons/MenuBarIcon.svg \
    -o Resources/JotwayMenuBarTemplate.pdf

echo "图标已导出：Resources/AppIcon.icns、Resources/JotwayMenuBarTemplate.pdf"
