#!/usr/bin/env python3
"""Build a local DMG and release metadata without publishing or enabling online updates."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
RELEASE = ROOT / "release"
APP_NAME = "Jotway"


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


def choose_version(requested, info, releases):
    current = info["CFBundleShortVersionString"]
    build = int(info["CFBundleVersion"])
    for item in releases:
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
    return version, build + 1


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


def release(args):
    info = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())
    version, build = choose_version(args.version, info, release_versions())
    output = RELEASE / f"{version}-{build}"
    if output.exists():
        raise ValueError(f"产物目录已存在：{output}。请先检查上次失败的产物，或指定其他版本。")
    if os.uname().machine != "arm64":
        raise ValueError("当前发布流程只支持 arm64。")
    notes, source_commit = release_notes(args.notes)
    print(f"==> {APP_NAME} {version} ({build}) → {output}", flush=True)
    print(f"==> 更新说明\n{notes}\n", flush=True)
    if args.dry_run:
        print("预览：构建 release App → 本地 DMG → SHA-256 校验 → 本地发行记录；不上传，不启用在线更新。")
        return
    RELEASE.mkdir(exist_ok=True)
    # Only one release can build and write release metadata at a time.
    lock = RELEASE / ".release.lock"
    try:
        descriptor = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError:
        raise ValueError("另一个 release 正在运行；若进程已结束，请检查后移除 release/.release.lock。")
    os.close(descriptor)
    try:
        if choose_version(args.version, info, release_versions()) != (version, build):
            raise ValueError("发行记录已被另一个 release 更新，请重新运行以选择新构建号。")
        print("==> 构建本地 release 包", flush=True)
        run(ROOT / "scripts/build-app.sh", "release")
        output.mkdir()
        with tempfile.TemporaryDirectory(prefix=".stage-", dir=output) as temp:
            stage = Path(temp)
            app = stage / f"{APP_NAME}.app"
            run("ditto", ROOT / f"{APP_NAME}.app", app)
            bundled_info = app / "Contents/Info.plist"
            info = plistlib.loads(bundled_info.read_bytes())
            info.update(CFBundleShortVersionString=version, CFBundleVersion=str(build), JotwayUpdatesEnabled=False)
            info.pop("SUFeedURL", None)
            info.pop("SUPublicEDKey", None)
            bundled_info.write_bytes(plistlib.dumps(info, sort_keys=False))
            run("codesign", "--force", "--sign", "-", "--entitlements", ROOT / "Resources/Jotway.entitlements", app)
            run("codesign", "--verify", "--deep", "--strict", app)
            dmg = output / f"{APP_NAME}-{version}-{build}-arm64.dmg"
            create_dmg(stage, dmg)
        run("hdiutil", "verify", dmg)
        digest = sha256(dmg)
        metadata = {"version": version, "build": build, "file": dmg.name, "sha256": digest,
                    "sourceCommit": source_commit, "notes": notes,
                    "bytes": dmg.stat().st_size, "architecture": "arm64",
                    "codeSigning": "ad-hoc", "notarized": False, "published": False}
        (output / "release.json").write_text(json.dumps(metadata, indent=2, ensure_ascii=False) + "\n")
        print(f"\n本地 DMG：{dmg}\nSHA-256：{digest}\n发行记录：{output / 'release.json'}")
        print("应用包为 ad-hoc 签名，未公证；未上传，在线更新关闭。")
    finally:
        lock.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version", nargs="?", default="patch", help="patch（默认）/ minor / major / x.y.z")
    parser.add_argument("--notes", required=True, help="手动填写更新说明（必填）")
    parser.add_argument("--dry-run", action="store_true", help="预览下一版本和更新说明，不构建或写入文件")
    args = parser.parse_args()
    try:
        release(args)
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        print(f"release 失败：{error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
