# Website and product usage images

> Role: **Current**

The repository contains a static English-language website at `website/`. It is published at [liugq5713.github.io/jotway](https://liugq5713.github.io/jotway/) through GitHub Pages. The site currently reports that no public app release is available until a stable GitHub Release is verified.

## Pages and behavior

- `/`: quick record flow, four example Actions, recovery, optional AI, and privacy summary. The primary call to action points to the download page. Until a public artifact is registered it says “Check availability”.
- `/download/`: unpublished state or generated artifact facts, installation instructions, and source-build guidance. Directory routes also resolve from `/download` on a directory-index static host.
- `/privacy/`: draft lifetime, Action transfer, optional provider requests, full-text local feedback, retention and clearing boundaries. `/privacy` resolves in the same way.

Pages share `website/src/layout.html`, local styles, navigation and footer. A small dependency-free script drives the interactive product demo and copies an available checksum. Reading and navigation work without JavaScript. The site has no account system, analytics, external fonts or persistent browser preferences.

Action cards are examples, not the total Action count. Product copy follows the Current product and integration documents. Date extraction depends on per-action DeepSeek processing; it is not promised as an AI-free feature. Jev can send draft text before Enter; accepted local feedback has no retention limit or clear UI.

## Interactive product demo

The home page shows only the quick record panel: animated sample text and its Action confirmation button. It has no demo heading, surrounding frame, progress steps, Action tabs, playback toolbar, or success card. The simulation is described for assistive technology and in the privacy page; it never executes an Action, opens an application, sends a request, or persists a visitor's choices.

Seven predefined examples rotate automatically through Notes, Reminders, Google Search, and Calendar. Examples start with commands such as `notes:`, `remind me to`, and `search`. Each cycle opens an empty panel, types the sentence, shows the suggested Action, illustrates confirmation, dissolves the entire panel, and pauses briefly before the next example. The sample text is static content; the website performs no real intent recognition.

The 500 ms exit matches the app's Drift Away motion: the background, border, text, and Action button break apart from right to left into small pieces that drift upward and right while shrinking and fading. A viewport-sized canvas texture follows the panel's actual DOM layout and text wrapping, allowing fragments to travel beyond the card without adding horizontal page overflow. There is no replacement result card. Scrolling or resizing during the effect clears the old texture and proceeds to the pause before the next example.

Clicking the panel or pressing Space while it has keyboard focus pauses or resumes the current frame. Escape pauses, and Enter or the Action button confirms a suggested example. Keyboard focus remains on a usable element during the exit. Playback uses one animation-frame callback and stops while paused, offscreen, or on a hidden page. Returning resumes from that frame; no hidden time is replayed. Screen-reader status messages report explicit interaction without announcing each typed character or automatic cycle.

Reduced-motion mode shows a complete, static example, with no typing, particles, or automatic rotation. Its Action button advances to the next static example. Without JavaScript, the empty panel and the rest of the page remain readable, and the unavailable confirmation button stays hidden.

## Build and preview

The builder uses only Python 3’s standard library. Node.js is used solely for the workflow’s JavaScript syntax check:

```bash
python3 scripts/website/build.py
node --check website/src/site.js
python3 -m http.server 8765 --bind 127.0.0.1 --directory website/dist
```

Open `http://127.0.0.1:8765/`. Stop the server after review and confirm its port is no longer listening. `website/dist/` is disposable, ignored build output. GitHub Pages publishes it with directory-index routing, so `/`, `/download/` and `/privacy/` resolve under the project path. The deployment workflow is `.github/workflows/pages.yml` and runs for website changes on `main` or manually.

The build validates the release contract, copies the app icon and local CSS/JavaScript, expands the shared layout and release facts, rejects Chinese UI text, and checks local references and fragment targets. It emits relative links for the `/jotway/` project path and versions shared assets by their content hash. The Pages workflow builds the site, checks JavaScript syntax, and uploads `website/dist/`. Missing assets or invalid metadata fail the build. It does not fetch a release or start a server.

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

The exporter requires `gh`, inspects the actual release and matching uploaded asset, rejects draft/prerelease or mismatched artifacts, then downloads the public URL without credentials and verifies its size and SHA-256 against the local artifact. Publication date and URLs come from GitHub; version, build, minimum OS, architecture, filename, size, hash, signing and notarization come from the artifact record. Notes come from that same record. If they contain Chinese text, the English page links to the unchanged original notes in `release.json` instead of inventing a translation. No page separately defines these facts. The exporter never uploads a release or deploys a site.

The tag workflow runs this exporter after creating the GitHub Release, builds the site with the exported metadata, and uploads the static site as a separate workflow artifact. That artifact is ready for a separately selected hosting target; it is not automatically deployed. Bring its `release.json` back into the checked-in website input if subsequent default local builds should use that release.

For a local download rehearsal using a real, verified DMG:

```bash
python3 scripts/website/build.py --local-release release/<version-build>/release.json
```

This copies the matching DMG into the ignored site's `downloads/` directory and explicitly labels it “Local preview · Not publicly released”. It displays the packaging date, not a publication date. A normal build rejects local-preview metadata; rerun the default build before preparing the unpublished site for deployment. Older local release records that lack minimum OS or creation time must be rebuilt, not backfilled with guessed values.

## Canonical usage images

`Resources/Screenshots/` supplies both READMEs. These images are independent of the website’s DOM demo and are not copied into the website build:

- `launcher-light.png` and `launcher-dark.png` render the production `EditorView` at 2× with synthetic text and the actual English labels.
- Empty-state captures provide the first walkthrough frame.
- `chrome-search.png` is a cropped real Chrome page for the same synthetic search, excluding account controls and personal information.
- `README-flow.png` composes those captures into three numbered steps with annotations outside the application UI. It is a walkthrough, not an end-to-end execution recording or a history view.
- `provenance.json` records the UI source hashes. See the [capture reference](../../Resources/Screenshots/README.md) for reproduction.

The renderer links the debug product objects and supplies its own entry point. It does not invoke `JotwayApp`, instantiate `AppState`, read user storage, enumerate installed apps or execute an Action. Source build and current UI screenshots can be reviewed before any public release exists. A future release must be checked against these UI source hashes and product claims before publication; regenerate images when relevant UI changes.
