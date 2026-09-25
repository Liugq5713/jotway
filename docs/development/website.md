# Website and product usage images

> Role: **Current**

The repository contains a static Chinese-language website at `website/`. It is locally buildable; this document does not imply that a public website or download has been deployed. The remaining publication scope is in [Website publication](../product/website-publishing.md).

## Pages and behavior

- `/`: quick record flow, four example Actions, recovery, optional AI, and privacy summary. The primary call to action points to the download page. Until a public artifact is registered it says “查看下载状态”.
- `/download/`: unpublished state or generated artifact facts, installation instructions, and source-build guidance. Directory routes also resolve from `/download` on a directory-index static host.
- `/privacy/`: draft lifetime, Action transfer, optional provider requests, full-text local feedback, retention and clearing boundaries. `/privacy` resolves in the same way.

Pages share `website/src/layout.html`, local styles, navigation and footer. The only JavaScript switches the real light/dark panel image and copies an available checksum. Reading and navigation work without JavaScript. The site has no account system, analytics, external fonts or persistent browser preferences.

Action cards are examples, not the total Action count. Product copy follows the Current product and integration documents. Date extraction depends on per-action DeepSeek processing; it is not promised as an AI-free feature. Jev can send draft text before Enter; accepted local feedback has no retention limit or clear UI.

## Build and preview

Only Python 3's standard library is required for the website:

```bash
python3 scripts/website/build.py
python3 -m http.server 8765 --bind 127.0.0.1 --directory website/dist
```

Open `http://127.0.0.1:8765/`. Stop the server after review and confirm its port is no longer listening. `website/dist/` is disposable, ignored build output. Host that directory with directory-index routing to preserve all three routes. No hosting identity or domain is configured by the build.

The build validates the release contract, copies the canonical screenshots, expands the shared layout and release facts, and checks local references and fragment targets. Missing assets or invalid metadata fail the build. It does not fetch a release or start a server.

## Download metadata

`website/release.json` is the sole input for the default build's release status. Its initial state is `unpublished`, containing no fictional version or download URL. Website HTML and READMEs do not carry a duplicate release version.

The artifact producer `scripts/release.py` reads bundle metadata from the packaged app, checks the ad-hoc signature, inspects the executable's architecture with `lipo`, and records minimum macOS, UTC creation time, actual byte length and SHA-256 alongside the existing version, build, notes and signing fields. Its local records remain unpublished. The pipeline does not submit artifacts for notarization.

After a real, stable GitHub Release exists, export the public metadata:

```bash
python3 scripts/website/publish-metadata.py \
  --release release/<version-build>/release.json \
  --tag v<version> \
  --output website/release.json
python3 scripts/website/build.py
```

The exporter requires `gh`, inspects the actual release and matching uploaded asset, rejects draft/prerelease or mismatched artifacts, then downloads the public URL without credentials and verifies its size and SHA-256 against the local artifact. Publication date and URLs come from GitHub; version, build, minimum OS, architecture, filename, size, hash, signing and notarization come from the artifact record. Notes come from that same record. No page separately defines these facts. The exporter never uploads a release or deploys a site.

The tag workflow runs this exporter after creating the GitHub Release, builds the site with the exported metadata, and uploads the static site as a separate workflow artifact. That artifact is ready for a separately selected hosting target; it is not automatically deployed. Bring its `release.json` back into the checked-in website input if subsequent default local builds should use that release.

For a local download rehearsal using a real, verified DMG:

```bash
python3 scripts/website/build.py --local-release release/<version-build>/release.json
```

This copies the matching DMG into the ignored site's `downloads/` directory and explicitly labels it “本地验证包 · 未公开发布”. It displays the packaging date, not a publication date. A normal build rejects local-preview metadata; rerun the default build before preparing the unpublished site for deployment. Older local release records that lack minimum OS or creation time must be rebuilt, not backfilled with guessed values.

## Canonical usage images

`Resources/Screenshots/` is shared by both READMEs and the site:

- `launcher-light.png` and `launcher-dark.png` render the production `EditorView` at 2× with synthetic text and the actual English labels.
- Empty-state captures provide the first walkthrough frame.
- `chrome-search.png` is a cropped real Chrome page for the same synthetic search, excluding account controls and personal information.
- `README-flow.png` composes those captures into three numbered steps with annotations outside the application UI. It is a walkthrough, not an end-to-end execution recording or a history view.
- `provenance.json` records the UI source hashes. See the [capture reference](../../Resources/Screenshots/README.md) for reproduction.

The renderer links the debug product objects and supplies its own entry point. It does not invoke `JotwayApp`, instantiate `AppState`, read user storage, enumerate installed apps or execute an Action. Source build and current UI screenshots can be reviewed before any public release exists. A future release must be checked against these UI source hashes and product claims before publication; regenerate images when relevant UI changes.
