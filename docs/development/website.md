# Website and product usage images

> Role: **Current**

The repository contains a static English-language website at `website/`. It is published at [liugq5713.github.io/jotway](https://liugq5713.github.io/jotway/) through GitHub Pages. Each deployment verifies the latest stable GitHub Release and updates the site's download details automatically.

## Pages and behavior

- `/`: quick record flow, four example Actions, recovery, optional AI, and privacy summary. The primary call to action says “Download Jotway” and downloads the verified public DMG directly. “Installation & details” opens the download page; an unpublished build says “Check availability” and opens that page instead.
- `/download/`: verified artifact facts, a DMG download, installation instructions, and source-build guidance. An unpublished build shows an availability message instead. Directory routes also resolve from `/download` on a directory-index static host.
- `/privacy/`: draft lifetime, Action transfer, optional provider requests, full-text local feedback, retention and clearing boundaries. `/privacy` resolves in the same way.

Pages share `website/src/layout.html`, local styles, navigation and footer. The top navigation includes the GitHub repository and a direct download using the same verified release URL as the home page, with “Check availability” as the fallback when no public artifact is available. The footer's “Install guide” keeps release details and installation instructions accessible. A small dependency-free script drives the interactive product demo and copies an available checksum. Reading, navigation and downloads work without JavaScript. The site has no account system, analytics, external fonts or persistent browser preferences.

Action cards are examples, not the total Action count. Product copy follows the Current product and integration documents. Date extraction depends on per-action DeepSeek processing; it is not promised as an AI-free feature. Jev can send draft text before Enter; accepted local feedback has no retention limit or clear UI.

## Interactive product demo

The home page contains a silent, 14-second walkthrough on a warm-gray canvas. A white panel takes a natural-language thought, shows its automatically suggested Action, illustrates Enter confirmation, and dissolves into particles. Black-and-white components use the existing blue accent. The locally bundled Geist font makes no third-party requests; its license and source are in `website/src/fonts/`.

Two seven-second examples show the automatic path: `An idea for the next design review` suggests Notes, and `Remind me to send the design draft` suggests Reminders. The Action label is a read-only indicator: there is no candidate menu, manual selection, explicit-selection dot, or cursor click on the Action. The website performs no real recognition and never executes an Action, opens an application, sends text, or persists a visitor choice. The native app still supports manual target selection.

Each example types on beats 2–6, reveals its suggestion on beat 7, illustrates Enter on beat 10, starts its 500 ms particle exit on beat 11, and returns to an empty panel on beat 13. The full loop uses a 120 BPM grid (28 beats). A deterministic `window.jotwayDemo.seek(seconds)` renders any frame independently, including the typing cursor, pointer, click feedback, content blur, panel geometry, and exit. Closed-form critically damped spring responses are summed for repeated target changes. Text stays at native layout resolution; no scaled layer or `will-change` is applied. The first and last frames coincide, including pointer position.

Enter shows submission acceptance, not successful saving. The particle exit carries the panel background, border, text, and Action label from right to left, drifting upward and right. Its texture is generated from each example's fixed pre-exit frame and actual DOM text wrapping, so seeking directly into the effect works without playing earlier frames. Particles stay inside the demo canvas. There is no success checkmark or receipt.

Clicking the demo or pressing Space while it has focus pauses or resumes. Escape pauses playback. Enter confirms a ready example without opening a selection menu. Keyboard focus remains on the demo during the exit. Screen-reader status messages describe explicit interactions without announcing every animated character or beat.

Playback uses one animation-frame callback and stops while paused, offscreen, or on a hidden page. Returning resumes without replaying hidden time. Reduced-motion mode shows a complete, static example and supports Enter without typing, particles, or automatic rotation. Without JavaScript, the empty panel and all other page content remain readable, and the Action indicator stays hidden.

## Build and preview

The builder uses only Python 3’s standard library. Node.js is used solely for the workflow’s JavaScript syntax check:

```bash
python3 scripts/website/build.py
node --check website/src/site.js
python3 -m http.server 8765 --bind 127.0.0.1 --directory website/dist
```

Open `http://127.0.0.1:8765/`. Stop the server after review and confirm its port is no longer listening. `website/dist/` is disposable, ignored build output. GitHub Pages publishes it with directory-index routing, so `/`, `/download/` and `/privacy/` resolve under the project path.

The build validates the release contract, copies the app icon and local CSS/JavaScript, expands the shared layout and release facts, rejects Chinese UI text, and checks local references and fragment targets. It emits relative links for the `/jotway/` project path and versions shared assets by their content hash. Online-enabled metadata also requires a matching `--appcast` input; the builder copies it to `appcast.xml` without changing its contents. The builder does not fetch a release or start a server. Missing assets or invalid metadata fail the build.

The deployment workflow is `.github/workflows/pages.yml`. It runs for website changes on `main`, manual dispatch, a successful completion of the `Release` workflow, or a stable GitHub Release being published, edited, or released. It always checks out `main`, exports verified metadata for GitHub's latest stable release into a runner temporary file, verifies and exports the release appcast, builds with that metadata and feed, checks JavaScript syntax, and deploys `website/dist/` to GitHub Pages. The update feed lives at `/jotway/appcast.xml`; its DMG URL, versions, size, architecture and minimum macOS must match the verified release, and the DMG EdDSA signature must verify against the public key in `Resources/Info.plist`. Pre-online releases produce an empty feed. Public-key verification uses OpenSSL (Homebrew OpenSSL on macOS when necessary). A failed release lookup, download verification, or build stops deployment and leaves the existing site in place.

The `workflow_run` trigger covers releases created with the repository's `GITHUB_TOKEN`, whose release events do not start another workflow. Release event triggers also cover manual publishing and edits; their dispatch job uses `actions: write` to request a deployment on `main`, respecting the Pages environment's branch restriction. Failed release workflows and draft/prerelease events cannot replace a queued deployment. This flow needs no personal access token, scheduled polling, or automatic commit of website metadata.

## Download metadata

`website/release.json` is a checked-in snapshot of a verified public release and the sole input for the default offline build's release status. Website HTML and READMEs do not carry a duplicate release version. Pages deployments always export fresh metadata and pass it to the builder, so later website changes cannot restore an older release from this snapshot.

The artifact producer `scripts/release.py` reads bundle metadata from the packaged app, checks the ad-hoc signature, inspects the executable's architecture with `lipo`, and records minimum macOS, UTC creation time, actual byte length and SHA-256 alongside the existing version, build, notes and signing fields. Its local records remain unpublished. The pipeline does not submit artifacts for notarization.

To refresh the offline snapshot from GitHub's latest stable release and build it:

```bash
python3 scripts/website/publish-metadata.py --output website/release.json --appcast-output /tmp/jotway-appcast.xml
python3 scripts/website/build.py --appcast /tmp/jotway-appcast.xml
```

To verify a specific release against a local artifact, the original explicit form remains available:

```bash
python3 scripts/website/publish-metadata.py \
  --release release/<version-build>/release.json \
  --tag v<version> \
  --output website/release.json
python3 scripts/website/build.py
```

The exporter requires `gh`. Without `--tag`, it selects GitHub's latest stable release. Without `--release`, it reads the original artifact record from that release's public `release.json` attachment. With `--release`, it first verifies the local DMG against the supplied record. Both modes inspect the actual release and matching uploaded asset, reject drafts, prereleases, or mismatched artifacts, then download the DMG's public URL without credentials and verify its size and SHA-256 against the artifact record.

Publication date and URLs come from GitHub; version, build, minimum OS, architecture, filename, size, hash, signing and notarization come from the artifact record. Notes come from that same record, with a link to the full GitHub Release. If the artifact notes contain Chinese text, the English page links to the unchanged original notes in `release.json` instead of inventing a translation. No page separately defines these facts. The exporter never uploads a release or deploys a site.

The tag workflow runs this exporter after creating the GitHub Release, builds the site with the exported metadata, and uploads the static site as a separate downloadable workflow artifact. Its successful completion starts the Pages workflow, which rebuilds from `main` with verified metadata for the latest stable release and deploys the result. It does not deploy the tag workflow's potentially older website templates.

For a local download rehearsal using a real, verified DMG:

```bash
python3 scripts/website/build.py --local-release release/<version-build>/release.json
```

This copies the matching DMG into the ignored site's `downloads/` directory and explicitly labels it “Local preview · Not publicly released”. It displays the packaging date, not a publication date. A normal build rejects local-preview metadata; rerun the default build to restore the checked-in release snapshot after a local rehearsal. Older local release records that lack minimum OS or creation time must be rebuilt, not backfilled with guessed values.

## Canonical usage images

`Resources/Screenshots/` supplies both READMEs. These images are independent of the website’s DOM demo and are not copied into the website build:

- `launcher-light.png` and `launcher-dark.png` render the production `EditorView` at 2× with synthetic text and the actual English labels.
- Empty-state captures provide the first walkthrough frame.
- `chrome-search.png` is a cropped real Chrome page for the same synthetic search, excluding account controls and personal information.
- `README-flow.png` composes those captures into three numbered steps with annotations outside the application UI. It is a walkthrough, not an end-to-end execution recording or a history view.
- `provenance.json` records the UI source hashes. See the [capture reference](../../Resources/Screenshots/README.md) for reproduction.

The renderer links the debug product objects and supplies its own entry point. It does not invoke `JotwayApp`, instantiate `AppState`, read user storage, enumerate installed apps or execute an Action. Source build and current UI screenshots can be reviewed before any public release exists. A future release must be checked against these UI source hashes and product claims before publication; regenerate images when relevant UI changes.
