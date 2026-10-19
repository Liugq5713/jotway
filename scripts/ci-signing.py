#!/usr/bin/env python3
"""Prepare an isolated macOS keychain for GitHub Actions releases."""
import argparse
import base64
import binascii
import json
import os
from pathlib import Path
import re
import secrets
import shlex
import shutil
import subprocess
import sys
import tempfile
from code_signing import resolve_identity

REQUIRED = (
    "JOTWAY_SIGNING_IDENTITY",
    "JOTWAY_SIGNING_CERTIFICATE_BASE64",
    "JOTWAY_SIGNING_CERTIFICATE_PASSWORD",
    "JOTWAY_NOTARY_API_KEY_BASE64",
    "JOTWAY_NOTARY_KEY_ID",
    "JOTWAY_NOTARY_ISSUER_ID",
)


def check_configuration():
    missing = [name for name in REQUIRED if not os.environ.get(name, "").strip()]
    if missing:
        raise ValueError("Missing GitHub Actions configuration: " + ", ".join(missing)
                         + ". Configure repository Actions secrets/variables before releasing.")
    if os.environ["JOTWAY_SIGNING_IDENTITY"].strip() == "-":
        raise ValueError("JOTWAY_SIGNING_IDENTITY must select a Developer ID certificate, not ad-hoc signing.")
    profile = os.environ.get("JOTWAY_NOTARY_PROFILE", "").strip() or "jotway-release"
    if not re.fullmatch(r"[A-Za-z0-9._-]{1,128}", profile):
        raise ValueError("JOTWAY_NOTARY_PROFILE must be a simple keychain profile name.")
    return profile


def run(*arguments):
    try:
        return subprocess.run([str(arg) for arg in arguments], check=True,
                              capture_output=True, text=True).stdout
    except subprocess.CalledProcessError as error:
        # Native command arguments can contain passwords. Never include the
        # exception, command line, or credential-bearing output in annotations.
        raise ValueError(f"CI signing command failed: {arguments[0]} {arguments[1]} "
                         f"(exit {error.returncode}). Check the configured certificate and Apple credentials.") from None


def export(name, value):
    if "\n" in value or "\r" in value:
        raise ValueError("Invalid multiline CI signing path/profile.")
    with Path(os.environ["GITHUB_ENV"]).open("a") as stream:
        stream.write(f"{name}={value}\n")


def prepare():
    profile = check_configuration()
    if sys.platform != "darwin":
        raise ValueError("CI signing setup requires macOS.")
    # Native tools receive files/explicit arguments, not encoded private keys in
    # their process environment. The identity itself is non-secret metadata.
    configuration = {name: os.environ.pop(name) for name in REQUIRED if name != "JOTWAY_SIGNING_IDENTITY"}
    os.umask(0o077)
    directory = Path(tempfile.mkdtemp(prefix="jotway-signing-", dir=os.environ["RUNNER_TEMP"]))
    export("JOTWAY_SIGNING_DIRECTORY", str(directory))
    keychain = directory / "signing.keychain-db"
    previous = shlex.split(run("security", "list-keychains", "-d", "user"))
    (directory / "previous-keychains.json").write_text(json.dumps(previous))
    certificate, api_key = directory / "certificate.p12", directory / "AuthKey.p8"
    try:
        for path, name in ((certificate, "JOTWAY_SIGNING_CERTIFICATE_BASE64"),
                           (api_key, "JOTWAY_NOTARY_API_KEY_BASE64")):
            try:
                content = base64.b64decode("".join(configuration[name].split()), validate=True)
            except (ValueError, binascii.Error):
                raise ValueError(f"{name} must contain a valid base64-encoded file.") from None
            if not content:
                raise ValueError(f"{name} decodes to an empty file.")
            path.write_bytes(content)
        password = secrets.token_urlsafe(32)
        run("security", "create-keychain", "-p", password, keychain)
        run("security", "set-keychain-settings", "-lut", "21600", keychain)
        run("security", "unlock-keychain", "-p", password, keychain)
        run("security", "import", certificate, "-k", keychain,
            "-P", configuration["JOTWAY_SIGNING_CERTIFICATE_PASSWORD"], "-f", "pkcs12", "-t", "cert",
            "-T", "/usr/bin/codesign", "-T", "/usr/bin/security")
        run("security", "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:",
            "-s", "-k", password, keychain)
        run("security", "list-keychains", "-d", "user", "-s", keychain, *previous)
        identity = resolve_identity()
        imported = run("security", "find-identity", "-v", "-p", "codesigning", keychain)
        if identity not in re.findall(r"\b[0-9A-Fa-f]{40}\b", imported.upper()):
            raise ValueError("The imported certificate does not match JOTWAY_SIGNING_IDENTITY.")
        run("xcrun", "notarytool", "store-credentials", profile, "--key", api_key,
            "--key-id", configuration["JOTWAY_NOTARY_KEY_ID"],
            "--issuer", configuration["JOTWAY_NOTARY_ISSUER_ID"], "--keychain", keychain)
        export("JOTWAY_SIGNING_KEYCHAIN", str(keychain))
        export("JOTWAY_NOTARY_PROFILE", profile)
        print("Configured signing identity imported and Apple notarization credentials validated.")
    finally:
        certificate.unlink(missing_ok=True)
        api_key.unlink(missing_ok=True)


def cleanup():
    value = os.environ.get("JOTWAY_SIGNING_DIRECTORY")
    if not value:
        return
    directory = Path(value)
    if (directory.is_symlink() or directory.resolve().parent != Path(os.environ["RUNNER_TEMP"]).resolve()
            or not directory.name.startswith("jotway-signing-")):
        raise ValueError("Refusing to clean an unexpected CI signing directory.")
    if not directory.exists():
        return
    try:
        state = directory / "previous-keychains.json"
        if state.exists():
            previous = json.loads(state.read_text())
            run("security", "list-keychains", "-d", "user", "-s", *previous)
        keychain = directory / "signing.keychain-db"
        if keychain.exists():
            run("security", "delete-keychain", keychain)
    finally:
        shutil.rmtree(directory)
    print("Temporary release keychain and credential files removed.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("check", "prepare", "cleanup"))
    args = parser.parse_args()
    try:
        if args.command == "prepare":
            prepare()
        elif args.command == "cleanup":
            cleanup()
        else:
            check_configuration()
            print("Required CI signing configuration is present; credential validity is checked during prepare.")
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError) as error:
        message = ("Signing identity lookup failed; check the imported certificate."
                   if isinstance(error, subprocess.CalledProcessError) else str(error))
        print(f"::error::{message}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
