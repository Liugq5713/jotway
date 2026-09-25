#!/bin/bash
# 无需 Xcode 的开发构建：SwiftPM 编译 + 手工打包 .app + ad-hoc 签名
set -euo pipefail
cd "$(dirname "$0")/.."

APP="Jotway"
SWIFT_PRODUCT="Jotway"
CONFIG="debug"
UPDATE=false

for argument in "$@"; do
    case "$argument" in
        debug|release) CONFIG="$argument" ;;
        --update) UPDATE=true ;;
        -h|--help)
            echo "用法：$0 [debug|release] [--update]"
            echo "默认只构建；--update 只替换同一 Bundle ID 的 /Applications/Jotway.app，然后正常重启。"
            echo "更新前请暂存草稿，或提交正在编辑的记录。"
            echo "debug 与 release 均包含内置 action 和 AI Provider。"
            exit 0
            ;;
        *) echo "未知参数：${argument}（使用 --help 查看用法）" >&2; exit 1 ;;
    esac
done

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN=".build/$CONFIG/$SWIFT_PRODUCT"
APP_DIR="$APP.app"
SIGNING_ENTITLEMENTS="Resources/Jotway.entitlements"

echo "==> 打包 $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN" "$APP_DIR/Contents/MacOS/$APP"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/JotwayMenuBarTemplate.pdf "$APP_DIR/Contents/Resources/"

echo "==> 嵌入 Sparkle（保留符号链接，先签名内层服务）"
mkdir -p "$APP_DIR/Contents/Frameworks"
ditto ".build/$CONFIG/Sparkle.framework" "$APP_DIR/Contents/Frameworks/Sparkle.framework"
mkdir -p "$APP_DIR/Contents/Resources/Licenses"
cp .build/artifacts/sparkle/Sparkle/LICENSE "$APP_DIR/Contents/Resources/Licenses/Sparkle-LICENSE.txt"
cp .build/checkouts/GRDB.swift/LICENSE "$APP_DIR/Contents/Resources/Licenses/GRDB-LICENSE.txt"
cp Vendor/KeyboardShortcuts/license "$APP_DIR/Contents/Resources/Licenses/KeyboardShortcuts-LICENSE.txt"
SPARKLE="$APP_DIR/Contents/Frameworks/Sparkle.framework/Versions/B"
codesign --force --sign - --options runtime "$SPARKLE/XPCServices/Installer.xpc"
codesign --force --sign - --options runtime --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
codesign --force --sign - --options runtime "$SPARKLE/Autoupdate"
codesign --force --sign - --options runtime "$SPARKLE/Updater.app"
codesign --force --sign - "$APP_DIR/Contents/Frameworks/Sparkle.framework"

# 本地替换 release 包时延续已安装版本，避免被源 plist 的开发版本号降级。
if [ "$CONFIG" = release ] && [ "$UPDATE" = true ]; then
    python3 - "$APP_DIR/Contents/Info.plist" <<'PY'
from pathlib import Path
import plistlib
import sys

path = Path(sys.argv[1])
info = plistlib.loads(path.read_bytes())
for name in ("Jotway",):
    installed_path = Path(f"/Applications/{name}.app/Contents/Info.plist")
    if not installed_path.exists():
        continue
    installed = plistlib.loads(installed_path.read_bytes())
    if (installed.get("CFBundleIdentifier") == info["CFBundleIdentifier"]
            and int(installed.get("CFBundleVersion", "0")) >= int(info["CFBundleVersion"])):
        for field in ("CFBundleShortVersionString", "CFBundleVersion"):
            info[field] = installed[field]
path.write_bytes(plistlib.dumps(info, sort_keys=False))
PY
fi

# SwiftPM 资源 bundle（KeyboardShortcuts 的本地化等）：
# 实体进 Contents/Resources（参与签名封存）
for bundle in .build/"$CONFIG"/*.bundle; do
    [ -e "$bundle" ] || continue
    cp -R "$bundle" "$APP_DIR/Contents/Resources/"
done

# The current product is English-only. Nested package bundles choose their own preferred
# localization, so remove their additional translations from the packaged app as well.
while IFS= read -r -d '' localization; do
    case "$(basename "$localization")" in
        en.lproj|Base.lproj) ;;
        *) rm -rf -- "$localization" ;;
    esac
done < <(find "$APP_DIR/Contents/Resources" -type d -name '*.lproj' -print0)

# Permission prompts are read from the main application bundle, not the SwiftPM resource bundle.
for localization in Sources/Resources/*.lproj; do
    [ -f "$localization/InfoPlist.strings" ] || continue
    destination="$APP_DIR/Contents/Resources/$(basename "$localization")"
    mkdir -p "$destination"
    cp "$localization/InfoPlist.strings" "$destination/InfoPlist.strings"
done

echo "==> ad-hoc 签名（含 entitlements）"
codesign --force --sign - --entitlements "$SIGNING_ENTITLEMENTS" "$APP_DIR"

# 资源从 Contents/Resources 读取，签名后不再修改应用包。
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

echo "==> 完成：$PWD/$APP_DIR"
if [ "$UPDATE" = false ]; then
    echo "    更新安装版并重启：./scripts/build-app.sh $CONFIG --update"
    exit 0
fi

INSTALL_DIR="/Applications/$APP.app"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_DIR/Contents/Info.plist")

# 只替换同一 Bundle ID 的应用，其他应用和数据保持原样。
for installed in "$INSTALL_DIR"; do
    if [ -e "$installed" ]; then
        installed_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$installed/Contents/Info.plist")
        if [ "$installed_id" != "$BUNDLE_ID" ]; then
            echo "安装路径属于另一个应用，已停止更新：$installed" >&2
            exit 1
        fi
    fi
done

# diff -r 会跟随 framework 的多个目录符号链接；这里只读比较链接、权限及文件内容。
verify_copy() {
    python3 - "$1" "$2" <<'PY'
import hashlib
import os
from pathlib import Path
import sys

def manifest(root):
    entries = {}
    for base, directories, files in os.walk(root, followlinks=False):
        for name in directories + files:
            path = Path(base) / name
            if path.is_symlink():
                content = os.readlink(path)
            elif path.is_dir():
                content = None
            else:
                digest = hashlib.sha256()
                with path.open("rb") as stream:
                    for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                        digest.update(chunk)
                content = digest.hexdigest()
            entries[path.relative_to(root)] = (path.lstat().st_mode, content)
    return entries

original, copied = [manifest(Path(value)) for value in sys.argv[1:]]
differences = sorted(str(path) for path in original.keys() | copied.keys() if original.get(path) != copied.get(path))
if differences:
    raise SystemExit("应用副本与构建产物不一致：\n" + "\n".join(differences))
PY
}

# 先复制并验证，确保构建、签名或复制失败时，正在使用的安装版不受影响。
STAGING_DIR=$(mktemp -d "/Applications/.Jotway-update.XXXXXX")
trap 'rm -rf "$STAGING_DIR"' EXIT
ditto "$APP_DIR" "$STAGING_DIR/$APP.app"
codesign --verify --strict "$STAGING_DIR/$APP.app"
verify_copy "$APP_DIR" "$STAGING_DIR/$APP.app"

# 正常退出与启动后核对都按 Bundle ID 查进程，涵盖从项目目录启动的副本。
jotway_process() {
    swift - "$1" "$BUNDLE_ID" "$INSTALL_DIR" <<'SWIFT'
import AppKit

let action = CommandLine.arguments[1]
let identifier = CommandLine.arguments[2]
let installURL = URL(fileURLWithPath: CommandLine.arguments[3]).resolvingSymlinksInPath()
let deadline = Date().addingTimeInterval(10)

if action == "quit" {
    let applications = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
    for application in applications where !application.isTerminated {
        print("==> 正常退出：PID \(application.processIdentifier)，\(application.bundleURL?.path ?? "未知路径")")
        guard application.terminate() else {
            fputs("Jotway 未接受退出请求，已停止更新。请暂存内容并从菜单退出后重试。\n", stderr)
            exit(1)
        }
    }
    while Date() < deadline {
        if NSRunningApplication.runningApplications(withBundleIdentifier: identifier).isEmpty {
            exit(0)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    fputs("Jotway 在 10 秒内未退出，已停止更新，未强制终止进程。\n", stderr)
} else {
    while Date() < deadline {
        let applications = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
        if applications.count == 1, let application = applications.first,
           application.isFinishedLaunching,
           application.bundleURL?.resolvingSymlinksInPath() == installURL {
            print("==> 已启动：PID \(application.processIdentifier)，\(installURL.path)")
            print("    进程启动时间：\(application.launchDate?.description ?? "未知")")
            exit(0)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    fputs("未确认新版 Jotway 正常启动；安装包已更新，请检查应用是否退出或有其他副本运行。\n", stderr)
}
exit(1)
SWIFT
}

jotway_process quit

rm -rf "$INSTALL_DIR"
if ! mv "$STAGING_DIR/$APP.app" "$INSTALL_DIR"; then
    echo "安装失败，已停止启动。项目内的新版应用包仍在：$PWD/$APP_DIR" >&2
    exit 1
fi
codesign --verify --strict "$INSTALL_DIR"
verify_copy "$APP_DIR" "$INSTALL_DIR"


echo "==> 启动：$INSTALL_DIR"
open "$INSTALL_DIR" --args --jotway-update-relaunch
jotway_process verify
