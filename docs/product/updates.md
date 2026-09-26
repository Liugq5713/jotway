# App updates and release

> Role: **Current**

Jotway includes Sparkle, but packaged builds currently use local updates. GitHub Actions runs continuous build/test validation, publishes tag-triggered GitHub Releases, and automatically updates the website with verified download details. The published packages remain ad-hoc signed and do not enable Sparkle online updates.

## Client behavior

- Builds set `JotwayUpdatesEnabled` to false and contain no `SUFeedURL`. Settings → 关于 shows that the build uses local updates and disables update controls; no update check is sent.
- Sparkle can be enabled once a new HTTPS feed and EdDSA signing public key are configured. Its update checks start after the application finishes its critical startup path, and manual checks use Sparkle's standard UI.
- Before termination for an update, Jotway asks the panel controller to preserve any recoverable draft state; an unsafe exit is cancelled.

Updates within Jotway retain `com.liuguangqi.jotway` and preserve its data. Installations with another bundle identifier are separate applications and are never imported or replaced automatically.

## Release flow

Preview:

```bash
./scripts/release.py --dry-run --notes "本次更新内容"
```

Build a local patch release:

```bash
./scripts/release.py patch --notes "本次更新内容"
```

`release.py`:

1. selects the next display/build version from the source metadata (initially 0.1.0, build 1) and existing `release/*/release.json` records;
2. validates the manually written release notes;
3. builds the release application with bundled actions and AI providers;
4. writes the version into the release copy and keeps online updates disabled;
5. ad-hoc signs and verifies the application, then creates and verifies the DMG;
6. calculates the DMG SHA-256 and writes local release metadata.

This command does not upload files, read login credentials, create update-signing keys, or generate an appcast. GitHub Releases are published only by the tag-triggered workflow described below; a replacement Sparkle update feed is not yet configured.

## GitHub Actions release

Pull requests and pushes to `main` run `swift build` and `swift test` on an arm64 macOS runner. A semver tag such as `v0.1.1` starts the release workflow, which:

1. builds the release application;
2. creates and verifies the arm64 DMG;
3. records the SHA-256 checksum and release metadata;
4. uploads the DMG and metadata as workflow artifacts;
5. creates a GitHub Release with the same files attached; and
6. verifies the public download against the local artifact and builds a separate downloadable [website artifact](../development/website.md) containing its generated metadata.

When the release workflow succeeds, the Pages workflow checks out `main`, fetches GitHub's latest stable release and its artifact metadata, verifies the public DMG's size and SHA-256 without download credentials, then rebuilds and deploys the website. It also runs for stable release publishing or edits, website changes on `main`, and manual dispatch. Every deployment resolves the latest stable release rather than using the checked-in offline metadata snapshot. Verification or build failures leave the deployed site unchanged.

The workflows use the repository's `GITHUB_TOKEN` for creating the GitHub Release and reading its published asset metadata. Pages listens for successful release workflow completion because release events created with this token do not trigger another workflow. Website synchronization needs no personal access token, scheduled task, or automatic metadata commit. Packaging does not require Apple credentials or Sparkle signing keys because the artifact is ad-hoc signed, not notarized, and has online updates disabled.

Users can install a downloaded DMG by replacing the application. For local development delivery, `./scripts/build-app.sh release --update` replaces and restarts the installed application.

## Release notes

`--notes` is required for both previews and local release builds. Release notes are written by the releaser; the script does not infer them from commits or call an AI service. A dry run does not build or write files.

The tag workflow uses the version label as the artifact's notes and asks GitHub to generate the GitHub Release body. The website preserves the artifact's notes and links to the GitHub Release for its full description.

## Outputs

Each version directory under `release/` contains the DMG and `release.json`, including the version, build, filename, inspected architecture, minimum macOS, UTC creation time, size, SHA-256, notes, and source commit. The metadata marks the artifact as unpublished. Keep these local records so successive builds advance the version; build directories and versioned binary products remain untracked.

## Signing boundary

The current application uses ad-hoc macOS code signing and is not Apple-notarized. Local DMGs do not carry a Sparkle EdDSA update signature. Enabling online distribution will require a separate update-signing and hosting flow; Sparkle signatures do not replace Apple code signing or notarization.
