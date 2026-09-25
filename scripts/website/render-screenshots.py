#!/usr/bin/env python3
"""Build an isolated renderer linked to the actual debug UI; no app launch or user data."""
import json
import hashlib
import platform
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
subprocess.run(["swift", "build"], cwd=ROOT, check=True)
binary = Path(subprocess.check_output(["swift", "build", "--show-bin-path"], cwd=ROOT, text=True).strip())
objects = (binary / "Jotway.product/Objects.LinkFileList").read_text().splitlines()
# SwiftPM names the app entry Jotway_main; this renderer supplies its own main.
# Linking the app object retains ThemeMode and shortcut definitions without invoking the app.

output = ROOT / "Resources/Screenshots"
renderer = binary / "RenderScreenshots"
subprocess.run(["swiftc", "-parse-as-library", "-enable-testing", "-I", str(binary / "Modules"),
                "-Xcc", "-fmodule-map-file=" + str(ROOT / ".build/checkouts/GRDB.swift/Sources/GRDBSQLite/module.modulemap"),
                "-target", platform.machine() + "-apple-macosx15.0",
                "-F", str(binary), "-framework", "Sparkle", "-Xlinker", "-rpath", "-Xlinker", str(binary),
                str(ROOT / "scripts/website/RenderScreenshots.swift"), *objects, "-o", str(renderer)], cwd=ROOT, check=True)
subprocess.run([str(renderer), str(output)], cwd=ROOT, check=True)
sources = ["Sources/Features/Editor/EditorView.swift", "Sources/Features/Launcher/LauncherViewState.swift",
           "Sources/Window/LauncherMetrics.swift", "Sources/Resources/en.lproj/Localizable.strings"]
(output / "provenance.json").write_text(json.dumps({
    "capture": "Production EditorView in an offscreen NSHostingView, 2x.",
    "data": "Synthetic text only. No AppState, API keys, database, application catalog or action execution.",
    "sourceSHA256": {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in sources}
}, indent=2) + "\n")
print(f"Rendered production views into {output}")
