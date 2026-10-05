#!/usr/bin/env python3
"""Build a signed Sparkle update and DMG; use --offline for a local-only package."""
import argparse
import base64
import binascii
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from urllib.parse import urlsplit
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
RELEASE = ROOT / "release"
APP_NAME = "Jotway"
SPARKLE_BIN = ROOT / ".build/artifacts/sparkle/Sparkle/bin"
SPARKLE_KEY_FILE = ROOT / ".secrets/sparkle-private.key"
SPARKLE_NS = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
GITHUB_REPOSITORY = "Liugq5713/jotway"

# CryptoKit verifies against the public key embedded in the application, rather
# than trusting the signing tool's own key selection.
VERIFY_SIGNATURE_SWIFT = """
import CryptoKit
import Foundation

do {
    let arguments = CommandLine.arguments
    guard let keyData = Data(base64Encoded: arguments[1]),
          let signature = Data(base64Encoded: arguments[2]) else { exit(1) }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
    let data = try Data(contentsOf: URL(fileURLWithPath: arguments[3]), options: .mappedIfSafe)
    guard key.isValidSignature(signature, for: data) else { exit(1) }
} catch {
    exit(1)
}
"""


def run(*args, capture=False, **kwargs):
    return subprocess.run([str(arg) for arg in args], cwd=ROOT, check=True,
                          text=True, stdout=subprocess.PIPE if capture else None, **kwargs).stdout


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def release_versions():
    return [json.loads(path.read_text()) for path in sorted(RELEASE.glob("*/release.json"))]


def choose_version(requested, info, releases, timestamp=None, previous=None):
    current = info["CFBundleShortVersionString"]
    build = int(info["CFBundleVersion"])
    if previous is not None and not re.fullmatch(r"\d+\.\d+\.\d+", previous.get("version", "")):
        raise ValueError("上一稳定发行的版本必须是 x.y.z。")
    for item in [*releases, *([previous] if previous is not None else [])]:
        item_build = int(item["build"])
        if item_build >= build:
            build = item_build
            current = item["version"]
    if not re.fullmatch(r"\d+\.\d+\.\d+", current or ""):
        raise ValueError("当前显示版本必须是 x.y.z。")
    parts = list(map(int, current.split(".")))
    if requested in ("patch", "minor", "major"):
        index = {"major": 0, "minor": 1, "patch": 2}[requested]
        parts[index] += 1
        parts[index + 1:] = [0] * (2 - index)
        version = ".".join(map(str, parts))
    elif re.fullmatch(r"\d+\.\d+\.\d+", requested):
        version = requested
        if tuple(map(int, version.split("."))) < tuple(map(int, current.split("."))):
            raise ValueError("release 不生成低于已有发行记录的显示版本。")
    else:
        raise ValueError("版本参数须为 patch、minor、major 或 x.y.z。")
    if previous is not None and tuple(map(int, version.split("."))) <= tuple(map(int, previous["version"].split("."))):
        raise ValueError("在线发行版本必须高于已发布的上一稳定版本。")
    # Clean CI checkouts have no local release history. UTC seconds advance
    # across them; the local floor also handles multiple builds in one second.
    if timestamp is None:
        timestamp = int(datetime.now(timezone.utc).timestamp())
    return version, max(timestamp, build + 1)


def release_notes(explicit_notes):
    source_commit = run("git", "rev-parse", "--verify", "HEAD", capture=True).strip()
    if not explicit_notes or not explicit_notes.strip():
        raise ValueError("请用 --notes 手动填写更新说明。")
    if len(explicit_notes.encode("utf-8")) > 128_000:
        raise ValueError("更新说明超过 128 KB，请精简 --notes 内容。")
    return explicit_notes.strip(), source_commit


def create_dmg(stage, destination):
    """Package the prepared app with instructions readable before launching it."""
    (stage / "Applications").symlink_to("/Applications")
    shutil.copyfile(ROOT / "Resources/首次打开说明.txt", stage / "首次打开说明.txt")
    run("hdiutil", "create", "-volname", APP_NAME, "-srcfolder", stage, "-format", "UDZO", destination)


def update_configuration(info):
    if info.get("JotwayUpdatesEnabled") is not True:
        raise ValueError("在线发行要求 Resources/Info.plist 启用 JotwayUpdatesEnabled；本地包请使用 --offline。")
    feed_url = info.get("SUFeedURL", "")
    parsed = urlsplit(feed_url)
    if (parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password
            or parsed.query or parsed.fragment or not parsed.path.endswith("/appcast.xml")):
        raise ValueError("SUFeedURL 必须是无凭据的 HTTPS appcast.xml 地址。")
    public_key = info.get("SUPublicEDKey", "")
    try:
        if len(base64.b64decode(public_key, validate=True)) != 32:
            raise ValueError()
    except (binascii.Error, ValueError, TypeError):
        raise ValueError("SUPublicEDKey 必须是有效的 32 字节 Ed25519 公钥。") from None
    if info.get("LSMinimumSystemVersion") != "15.0":
        raise ValueError("当前在线发行流程要求最低系统版本为 macOS 15.0。")
    return feed_url, public_key


def load_private_key(private_key):
    if private_key is None:
        try:
            descriptor = os.open(SPARKLE_KEY_FILE, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        except FileNotFoundError:
            raise ValueError("缺少更新签名私钥：请设置 SPARKLE_PRIVATE_KEY，或提供 .secrets/sparkle-private.key。") from None
        except OSError:
            raise ValueError("无法读取 .secrets/sparkle-private.key；请使用当前用户拥有的普通文件，不允许符号链接。") from None
        with os.fdopen(descriptor, "r", encoding="utf-8") as stream:
            details = os.fstat(stream.fileno())
            if (not stat.S_ISREG(details.st_mode) or details.st_uid != os.geteuid()
                    or stat.S_IMODE(details.st_mode) & 0o077):
                raise ValueError(".secrets/sparkle-private.key 必须是当前用户拥有的普通文件，权限设为 600。")
            if details.st_size > 4096:
                raise ValueError(".secrets/sparkle-private.key 内容不是有效的 Sparkle 私钥。")
            try:
                private_key = stream.read(4096)
            except UnicodeError:
                raise ValueError(".secrets/sparkle-private.key 内容不是有效的 Sparkle 私钥。") from None
    private_key = private_key.strip()
    try:
        if len(base64.b64decode(private_key, validate=True)) not in (32, 96):
            raise ValueError()
    except (binascii.Error, ValueError):
        raise ValueError("更新签名私钥格式无效；请检查 SPARKLE_PRIVATE_KEY 或 .secrets/sparkle-private.key。") from None
    return private_key


def signing_command(tool, *arguments, private_key):
    if not private_key:
        raise ValueError("缺少更新签名私钥。")
    result = subprocess.run([str(SPARKLE_BIN / tool), "--ed-key-file", "-", *map(str, arguments)],
                            cwd=ROOT, text=True, capture_output=True,
                            input=private_key + "\n")
    # Some Sparkle errors include malformed input. Never forward their output
    # when a private key has been supplied, even on failure.
    if result.returncode:
        raise ValueError(f"Sparkle {tool} 失败（退出码 {result.returncode}）；请检查签名密钥和发行包。")
    return result.stdout.strip()


def verify_signature(path, signature, public_key):
    result = subprocess.run(["swift", "-module-cache-path", str(ROOT / ".build/release-signing-module-cache"),
                             "-e", VERIFY_SIGNATURE_SWIFT, public_key, signature, str(path)],
                            cwd=ROOT, text=True, capture_output=True)
    if result.returncode:
        raise ValueError(f"Ed25519 验证失败：{path.name} 的签名与应用内 SUPublicEDKey 不匹配，或 CryptoKit 无法运行。")


def check_signing_key(public_key, private_key):
    if not all((SPARKLE_BIN / tool).is_file() for tool in ("generate_appcast", "sign_update")):
        run("swift", "package", "resolve")
    with tempfile.TemporaryDirectory(prefix="jotway-signing-check-") as directory:
        challenge = Path(directory) / "challenge.bin"
        challenge.write_bytes(os.urandom(32))
        signature = signing_command("sign_update", "-p", challenge, private_key=private_key)
        verify_signature(challenge, signature, public_key)


def create_appcast(output, dmg, version, build, notes, public_key, private_key):
    download_prefix = f"https://github.com/{GITHUB_REPOSITORY}/releases/download/v{version}/"
    notes_path = dmg.with_suffix(".txt")
    notes_path.write_text(notes, encoding="utf-8")
    appcast = output / "appcast.xml"
    try:
        signing_command("generate_appcast", "--download-url-prefix", download_prefix,
                        "--embed-release-notes", "--maximum-deltas", "0", "--maximum-versions", "1",
                        "-o", appcast, output, private_key=private_key)
    finally:
        notes_path.unlink()
    items = ET.parse(appcast).findall("./channel/item")
    if len(items) != 1:
        raise ValueError("appcast 必须且只能包含本次发行版本。")
    item = items[0]
    expected = {"version": str(build), "shortVersionString": version,
                "minimumSystemVersion": "15.0", "hardwareRequirements": "arm64"}
    if any(item.findtext(SPARKLE_NS + field) != value for field, value in expected.items()):
        raise ValueError("appcast 的版本、最低系统版本或 arm64 限制与发行包不匹配。")
    description = item.find("description")
    if (description is None or description.get(SPARKLE_NS + "format") != "plain-text"
            or description.text != notes):
        raise ValueError("appcast 缺少完整的纯文本更新说明。")
    enclosure = item.find("enclosure")
    if (enclosure is None or enclosure.get("url") != download_prefix + dmg.name
            or enclosure.get("length") != str(dmg.stat().st_size)):
        raise ValueError("appcast 的 GitHub 下载地址或文件大小与 DMG 不匹配。")
    signature = enclosure.get(SPARKLE_NS + "edSignature", "")
    verify_signature(dmg, signature, public_key)
    return appcast


def release(args):
    # Keep the secret out of every child process's environment, including dry runs.
    environment_key = os.environ.pop("SPARKLE_PRIVATE_KEY", None)
    info = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())
    update_config = update_configuration(info) if not args.offline else None
    previous = json.loads(args.previous_release.read_text()) if args.previous_release else None
    timestamp = int(datetime.now(timezone.utc).timestamp())
    version, build = choose_version(args.version, info, release_versions(), timestamp, previous)
    output = RELEASE / f"{version}-{build}"
    if output.exists():
        raise ValueError(f"产物目录已存在：{output}。请先检查上次失败的产物，或指定其他版本。")
    if os.uname().machine != "arm64":
        raise ValueError("当前发布流程只支持 arm64。")
    notes, source_commit = release_notes(args.notes)
    print(f"==> {APP_NAME} {version} ({build}) → {output}", flush=True)
    print(f"==> 更新说明\n{notes}\n", flush=True)
    if args.dry_run:
        if args.offline:
            print("预览：构建 release App → 本地 DMG → SHA-256 校验 → 本地发行记录；在线更新关闭。")
        else:
            print(f"预览：校验签名密钥 → release App → DMG → 已签名 appcast.xml → 发行记录；更新源 {update_config[0]}。")
        print("预览不读取或验证私钥、不构建、不写入文件、不上传。")
        return
    private_key = load_private_key(environment_key) if update_config else None
    RELEASE.mkdir(exist_ok=True)
    # Only one release can build and write release metadata at a time.
    lock = RELEASE / ".release.lock"
    try:
        descriptor = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError:
        raise ValueError("另一个 release 正在运行；若进程已结束，请检查后移除 release/.release.lock。")
    os.close(descriptor)
    try:
        if choose_version(args.version, info, release_versions(), timestamp, previous) != (version, build):
            raise ValueError("发行记录已被另一个 release 更新，请重新运行以选择新构建号。")
        if update_config:
            print("==> 验证更新签名密钥", flush=True)
            check_signing_key(update_config[1], private_key)
        print("==> 构建 release 包", flush=True)
        run(ROOT / "scripts/build-app.sh", "release")
        output.mkdir()
        with tempfile.TemporaryDirectory(prefix=".stage-", dir=output) as temp:
            stage = Path(temp)
            app = stage / f"{APP_NAME}.app"
            run("ditto", ROOT / f"{APP_NAME}.app", app)
            bundled_info = app / "Contents/Info.plist"
            info = plistlib.loads(bundled_info.read_bytes())
            info.update(CFBundleShortVersionString=version, CFBundleVersion=str(build),
                        JotwayUpdatesEnabled=not args.offline)
            if args.offline:
                info.pop("SUFeedURL", None)
                info.pop("SUPublicEDKey", None)
            elif update_configuration(info) != update_config:
                raise ValueError("构建产物的更新配置与发行前校验的配置不一致。")
            bundled_info.write_bytes(plistlib.dumps(info, sort_keys=False))
            run("codesign", "--force", "--sign", "-", "--entitlements", ROOT / "Resources/Jotway.entitlements", app)
            run("codesign", "--verify", "--deep", "--strict", app)
            signature = subprocess.run(["codesign", "-dv", "--verbose=4", str(app)],
                                       check=True, text=True, capture_output=True).stderr
            if "Signature=adhoc" not in signature:
                raise ValueError("本地发行流程预期 ad-hoc 签名，但产物签名不匹配。")
            architecture = run("lipo", "-archs", app / "Contents/MacOS/Jotway", capture=True).strip()
            if architecture != "arm64":
                raise ValueError(f"发行包须仅包含 arm64，实际为 {architecture}。")
            dmg = output / f"{APP_NAME}-{version}-{build}-arm64.dmg"
            create_dmg(stage, dmg)
        run("hdiutil", "verify", dmg)
        appcast = None
        if update_config:
            appcast = create_appcast(output, dmg, version, build, notes, update_config[1], private_key)
        digest = sha256(dmg)
        metadata = {"version": version, "build": build, "file": dmg.name, "sha256": digest,
                    "sourceCommit": source_commit, "notes": notes,
                    "bytes": dmg.stat().st_size, "architecture": architecture,
                    "minimumMacOS": info["LSMinimumSystemVersion"],
                    "createdAt": datetime.now(timezone.utc).isoformat(),
                    "codeSigning": "ad-hoc", "notarized": False, "published": False,
                    "updatesEnabled": not args.offline}
        (output / "release.json").write_text(json.dumps(metadata, indent=2, ensure_ascii=False) + "\n")
        print(f"\n本地 DMG：{dmg}\nSHA-256：{digest}\n发行记录：{output / 'release.json'}")
        if appcast:
            print(f"已验证签名的更新清单：{appcast}")
        print(f"应用包为 ad-hoc 签名，未公证；未上传，在线更新{'关闭' if args.offline else '已启用'}。")
    finally:
        lock.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version", nargs="?", default="patch", help="patch（默认）/ minor / major / x.y.z")
    parser.add_argument("--notes", required=True, help="手动填写更新说明（必填）")
    parser.add_argument("--dry-run", action="store_true", help="预览下一版本和更新说明，不构建或写入文件")
    parser.add_argument("--offline", action="store_true", help="生成关闭在线更新的本地包，无需 Sparkle 私钥")
    parser.add_argument("--previous-release", type=Path,
                        help="经验证的上一稳定 release.json；新版本和构建号必须高于它")
    args = parser.parse_args()
    try:
        release(args)
    except (ValueError, KeyError, OSError, ET.ParseError, subprocess.CalledProcessError) as error:
        print(f"release 失败：{error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
