# Website and product usage images

> Role: **Current**

The repository contains a static English-language website at `website/`. The primary website is [jotway.pages.dev](https://jotway.pages.dev/), deployed to the Cloudflare Pages project `jotway` on its `main` production branch. The existing [GitHub Pages site](https://liugq5713.github.io/jotway/) has a separate deployment workflow that verifies the latest stable GitHub Release and updates its download details automatically.

Cloudflare currently uses GitHub Releases-only mode: download calls to action lead to the repository's Releases page, and the home and installation pages disclose that the available build is not notarized by Apple. This mode does not advertise a verified direct DMG, publish a Sparkle feed, or relax the signed-release exporter. Its `release.json` has `status: unpublished`, meaning this site advertises no verified installer, not that GitHub has no releases. The product demo remains explicitly labeled as a development preview.

## Cloudflare Pages deployment

Build the current Releases-only site and upload the generated static directory using an authenticated Wrangler installation:

```bash
python3 scripts/website/build.py --github-releases-only
node --check website/src/site.js
npx wrangler pages deploy website/dist --project-name jotway --branch main
```

Only `website/dist/` is uploaded. No Cloudflare Git integration or automatic deployment workflow is configured; source changes require another build and upload. The existing GitHub Pages workflow and application update URL remain independent. To enable direct downloads later, verify a notarized release with the exporter and build with its metadata and appcast instead of `--github-releases-only`.

## Pages and behavior

The following direct-download behavior applies to builds using verified release metadata. Releases-only mode uses the external download path described above.

- `/`: Apple Notes capture and local application launching, confirmation and illustrative destination results, recovery and privacy. The primary call to action says “Download Jotway” and downloads the verified public DMG directly. “Installation & details” opens the download page; an unpublished build says “Check availability” and opens that page instead.
- `/download/`: verified artifact facts, a DMG download, installation instructions, and source-build guidance. An unpublished build shows an availability message instead. Directory routes also resolve from `/download` on a directory-index static host.
- `/privacy/`: draft lifetime, Action transfer, optional provider requests, full-text local feedback, retention and clearing boundaries. `/privacy` resolves in the same way.
- `/terms/`: the Jotway individual-developer brand, free core features, planned paid AI service, renewal and cancellation, content and service boundaries.
- `/refunds/`: the planned 14-day full-refund offer for initial monthly or annual purchases and renewals, request instructions, and cancellation/access consequences.
- `/contact/`: the public support email `liugq5713@gmail.com`, billing and privacy request guidance. Residential account-verification addresses are not published on the website.

Pages share `website/src/layout.html`, local styles, navigation and footer. The top navigation includes the GitHub repository and a direct download using the same verified release URL as the home page, with “Check availability” as the fallback when no public artifact is available. The footer's “Install guide” keeps release details and installation instructions accessible. A small dependency-free script drives the interactive product demo and copies an available checksum. Reading, navigation and downloads work without JavaScript. The site has no account system, analytics, external fonts or persistent browser preferences.

The home page leads with Apple workflows. Other actions remain discoverable through the product guide. Enhanced examples are visibly labeled development previews requiring an unreleased source build; the download metadata is not evidence that a newer workspace feature is released. Privacy copy distinguishes local routing from optional Notes AI, Notes indexing, primary/fallback model disclosure and local records.

## AI pricing preview

The home page's `/#pricing` section is linked from every page's header and footer. It presents free core features alongside planned Jotway AI subscriptions: USD 4.99 monthly or USD 49 annually, both with a starting beta allowance of 500 AI points per month. Annual points are provided monthly. A planned one-time trial offers 30 points without a card. The point guide lists automatic title and grouping for one capture together at 1 point, a thinking prompt at 1 point, a deep insight at 5 points, and each weekly or monthly review at 20 points.

The section explicitly labels subscriptions, trial activation and point billing as forthcoming. Paid cards have informational availability labels, not purchase controls. It does not collect payment details, activate a trial, grant points or change the service's existing token accounting. Core capture, editing and saving original text are described as free. All pricing content is static and readable without JavaScript.

The footer links the terms, privacy, refunds and contact pages from every route. Terms and refunds explicitly describe the future paid offering rather than claiming checkout is available. Both monthly and annual purchases and renewals have a 14-day full-refund offer; using some AI points does not itself disqualify a timely request. Billing, cancellation, refunds and credit entitlement still need to be implemented and verified before enabling purchases. Privacy disclosures distinguish optional hosted AI, provider processing, website hosting, support messages and planned Paddle billing.

## Interactive product demo

The complete Notes HTML scene uses fictional content and shows input, review before confirmation, and an explicitly illustrative result. The original stays separate from optional indexed history and configured AI assistance. No retired action scene or synthetic time preview remains.

Without JavaScript the complete scene remains readable and controls stay hidden. With JavaScript the completed static scene is initially visible. One native button explicitly starts, pauses or resumes its six-second timeline: input at zero seconds, review at two and result at four. No automatic rotation occurs. `window.jotwayDemo.seek(seconds)` clamps time and pauses. Focus stays on the button; live status announces explicit interactions and completion.

Reduced motion keeps the full static scene and disables playback. Escape, page hiding and leaving the viewport pause it; returning never starts it automatically. The demo reads no personal data, opens no app, calls no model and persists no state. Download checksum copying stays independent.

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

Both READMEs currently omit screenshots. The retired Chrome-search captures have been removed. The website uses its independent synthetic HTML demonstration. [Capture tools](../../Resources/Screenshots/README.md) can regenerate offscreen production EditorView images with fictional Notes text and a two-stage pre-confirmation composite; they do not access Notes or a browser.

The renderer links the debug product objects and supplies its own entry point. It does not invoke `JotwayApp`, instantiate `AppState`, read user storage, enumerate installed apps or execute an Action. Source build and current UI screenshots can be reviewed before any public release exists. A future release must be checked against these UI source hashes and product claims before publication; regenerate images when relevant UI changes.
