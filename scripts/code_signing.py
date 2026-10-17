#!/usr/bin/env python3
"""Use one configured macOS signing identity throughout local packaging."""
import argparse
import os
import plistlib
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
IDENTITY_FILE = ROOT / ".secrets/signing-identity"


def resolve_identity():
    requested = os.environ.get("JOTWAY_SIGNING_IDENTITY")
    if requested is None:
        requested = IDENTITY_FILE.read_text().strip() if IDENTITY_FILE.exists() else "-"
    requested = requested.strip()
    if requested == "-":
        return requested
    if not requested:
        raise ValueError("签名身份不能为空；请配置证书 SHA-1 指纹，或明确使用 - 表示 ad-hoc。")
    identities = subprocess.run(["security", "find-identity", "-v", "-p", "codesigning"],
                                check=True, text=True, capture_output=True).stdout
    matches = {fingerprint.upper() for fingerprint, name in re.findall(
        r'^\s*\d+\)\s+([0-9A-Fa-f]{40})\s+"(.*)"\s*$', identities, re.MULTILINE)
        if fingerprint.lower() == requested.lower() or name == requested}
    if len(matches) != 1:
        raise ValueError("固定签名证书不可用或名称不唯一；请用 security find-identity -v -p codesigning "
                         "查询，并配置唯一的 SHA-1 指纹。不会回退为 ad-hoc 签名。")
    return matches.pop()


def sign_app(app, identity):
    app = Path(app)
    sparkle = app / "Contents/Frameworks/Sparkle.framework"
    inner = sparkle / "Versions/B"
    # Sign nested code before its enclosing bundle, using the same identity.
    targets = [
        (inner / "XPCServices/Installer.xpc", ["--options", "runtime"]),
        (inner / "XPCServices/Downloader.xpc", ["--options", "runtime", "--preserve-metadata=entitlements"]),
        (inner / "Autoupdate", ["--options", "runtime"]),
        (inner / "Updater.app", ["--options", "runtime"]),
        (sparkle, ["--options", "runtime"]),
        (app / "Contents/Helpers/JotwayClipboardOCR", ["--options", "runtime", "--entitlements", str(ROOT / "Resources/ClipboardOCR.entitlements")]),
    ]
    timestamp = "--timestamp=none" if identity == "-" else "--timestamp"
    for target, options in targets:
        if target != app / "Contents/Helpers/JotwayClipboardOCR":
            if "--preserve-metadata=entitlements" not in options:
                options = [*options, "--preserve-metadata=entitlements"]
        subprocess.run(["codesign", "--force", "--sign", identity, timestamp, *options, str(target)], check=True)
    with tempfile.TemporaryDirectory(prefix="jotway-signing-") as directory:
        main_entitlements = ROOT / "Resources/Jotway.entitlements"
        # Local ad-hoc and self-signed identities have no Apple Team ID, so
        # hardened library validation otherwise rejects the embedded Sparkle.
        if "TeamIdentifier=not set" in signature_details(sparkle).splitlines():
            entitlements = plistlib.loads(main_entitlements.read_bytes())
            entitlements["com.apple.security.cs.disable-library-validation"] = True
            main_entitlements = Path(directory) / "Jotway.entitlements"
            main_entitlements.write_bytes(plistlib.dumps(entitlements))
            print("Local signing without an Apple Team ID: enabling the main app's development library-validation exception.")
        subprocess.run(["codesign", "--force", "--sign", identity, timestamp,
                        "--options", "runtime", "--entitlements", str(main_entitlements), str(app)], check=True)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)


def signature_details(app):
    result = subprocess.run(["codesign", "-d", "--verbose=4", "-r-", str(app)],
                            check=True, text=True, capture_output=True)
    return result.stdout + result.stderr


def signing_kind(app):
    if "Signature=adhoc" in signature_details(app).splitlines():
        return "ad-hoc"
    # Check Apple's certificate extension, not the certificate's display name.
    developer_id = subprocess.run([
        "codesign", "--verify", "--strict", "-R=anchor apple generic and "
        "certificate leaf[field.1.2.840.113635.100.6.1.13] exists", str(app)
    ], capture_output=True)
    return "developer-id" if developer_id.returncode == 0 else "certificate"


def verify_distribution_app(app):
    """Read the signed artifacts, not merely the input entitlement files."""
    app = Path(app)
    helper = app / "Contents/Helpers/JotwayClipboardOCR"
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    for target in [app, helper, *sorted((app / "Contents/Frameworks").rglob("*.xpc")),
                   app / "Contents/Frameworks/Sparkle.framework",
                   app / "Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate",
                   app / "Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"]:
        details = signature_details(target)
        if signing_kind(target) != "developer-id" or "runtime" not in details or "Timestamp=" not in details:
            raise ValueError("Public distribution requires Developer ID, hardened runtime and a secure timestamp on every code object.")
    def entitlements(target):
        result = subprocess.run(["codesign", "-d", "--entitlements", "-", "--xml", str(target)],
                                check=True, capture_output=True)
        return plistlib.loads(result.stdout)
    main, child = entitlements(app), entitlements(helper)
    if main.get("com.apple.security.app-sandbox") or not main.get("com.apple.security.automation.apple-events"):
        raise ValueError("Main application runtime entitlements do not match direct distribution.")
    if main.get("com.apple.security.cs.disable-library-validation"):
        raise ValueError("Public distribution must not include the local library-validation exception.")
    if child.get("com.apple.security.app-sandbox") is not True or child.get("com.apple.security.inherit"):
        raise ValueError("OCR helper must have its own sandbox without inheritance.")


def verify_update(installed, replacement):
    installed = Path(installed)
    if not installed.exists():
        return
    old = signature_details(installed)
    if "Signature=adhoc" in old.splitlines():
        # An ad-hoc signature has no stable identity to preserve on migration.
        return
    new = signature_details(replacement)
    for details, target in ((old, replacement), (new, installed)):
        requirement = re.search(r'^(?:# )?designated => (.+)$', details, re.MULTILINE)
        if not requirement:
            raise ValueError("无法读取应用的签名身份要求，已停止更新。")
        result = subprocess.run(["codesign", "--verify", "--strict",
                                 "-R=" + requirement.group(1), str(target)],
                                capture_output=True)
        if result.returncode != 0:
            raise ValueError("新版与安装版的签名身份不兼容，已停止更新。请继续使用原证书；"
                             "更换证书需要单独迁移权限。安装版未被替换。")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("identity", help="只读检查并输出选定的证书指纹；- 表示 ad-hoc")
    sign = commands.add_parser("sign", help="签名并验证应用和内嵌服务")
    sign.add_argument("app", type=Path)
    update = commands.add_parser("check-update", help="只读检查新旧应用的签名身份兼容性")
    update.add_argument("installed", type=Path)
    update.add_argument("replacement", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "identity":
            print(resolve_identity())
        elif args.command == "sign":
            sign_app(args.app, resolve_identity())
        else:
            verify_update(args.installed, args.replacement)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"代码签名失败：{error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
