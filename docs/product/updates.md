# App updates and release

> Role: **Current**

Jotway uses Sparkle to check the HTTPS [GitHub Pages appcast](https://liugq5713.github.io/jotway/appcast.xml), download an EdDSA-signed DMG from GitHub Releases, and install it after the user confirms. Online releases require the configured signing key and a deployed feed. Existing builds that disabled Sparkle require a one-time manual installation of an online-enabled release.

## Client behavior

- Release packages embed `JotwayUpdatesEnabled=true`, the HTTPS `SUFeedURL`, and the Jotway `SUPublicEDKey`. Debug packages disable update checks. An explicit offline release also removes the feed and public key.
- Update checks start after the critical startup path. Automatic checks default to once every 24 hours and can be changed in Settings → About. The menu and About page support manual checks through Sparkle's standard UI.
- Downloaded updates must pass EdDSA verification before extraction. Automatic background installation is disabled; the user confirms installation and relaunch.
- Installation is postponed while an action is running, a failed submission remains recoverable, or the quick record panel has a nonempty draft. The user must handle those contents and retry. Input composition, action setup, and other unsafe termination states also block relaunch.
- Drafts live in memory and are not restored after relaunch. Ordinary application quit retains its existing behavior of clearing the draft.

Updates retain `com.liuguangqi.jotway` and preserve its persistent data. Installations with another bundle identifier are separate applications and are never imported or replaced automatically.

## Signing configuration

macOS code signing and Sparkle update signing are separate. The tag workflow publishes personal-developer builds: the application and nested services use ad-hoc signing, the DMG is unsigned, and Apple notarization is not requested. This needs no Developer ID certificate, Apple developer membership, or notarization credentials. The GitHub Release and website disclose that state. Sparkle signatures and SHA-256 verification remain required.

Local packaging can instead use the persistent certificate selected by `JOTWAY_SIGNING_IDENTITY` or `.secrets/signing-identity`; an unconfigured checkout uses ad-hoc signing. See [Stable local signing](../development/environment.md#stable-local-signing) for setup and permission continuity. A release without `--ad-hoc` or `--offline` explicitly selects Developer ID distribution and still requires the configured certificate and `JOTWAY_NOTARY_PROFILE`; missing credentials do not silently change that mode.

The public update key is checked into `Resources/Info.plist`. Its private key is stored in `.secrets/sparkle-private.key` at the repository root. The `.secrets` directory has mode `700`, the private-key file has mode `600`, and the directory is excluded from Git. Local online releases read this file; `SPARKLE_PRIVATE_KEY`, when provided, takes precedence. Dry runs do not read the private key.

The same private key must be configured as the repository Actions secret `SPARKLE_PRIVATE_KEY` before a tag can publish an online release. Provision it through the repository secret-management interface, never through committed workflow contents. The workflow fails when the secret is missing, and packaging rejects a private key that does not match the embedded public key before building the application.

Keep the local private-key file and a secure backup across builds and releases. Do not regenerate it for each release: installed clients trust the existing public key. Never commit, print, or pass the private key as a command-line argument. Local packaging and CI supply it to Sparkle through standard input.

The appcast and installer files are public. The signing key grants authority to sign Jotway updates and remains private.

## Local release flow

Preview without building, writing files, or reading the private key:

```bash
./scripts/release.py --ad-hoc --dry-run --notes "本次更新内容"
```

Build an online-enabled personal-developer release using `.secrets/sparkle-private.key`, or the `SPARKLE_PRIVATE_KEY` environment variable when supplied:

```bash
./scripts/release.py patch --ad-hoc --notes "本次更新内容"
```

For an offline package that needs no update-signing key:

```bash
./scripts/release.py patch --offline --notes "本次更新内容"
```

The script builds the release application with bundled actions and AI providers, writes display/build versions into the release copy, signs and verifies it, then creates and verifies the arm64 DMG. `--ad-hoc` explicitly uses ad-hoc application signing and leaves the DMG unsigned and unnotarized. Online packaging generates `appcast.xml` with Sparkle's `generate_appcast`, embeds the provided release notes, and verifies the DMG's update signature using the public key embedded in the application. The feed specifies the package's minimum macOS version and Apple silicon requirement. Only full updates are published.

`release.py` writes a local `release.json` containing version, build, filename, architecture, minimum macOS, creation time, byte length, SHA-256, release notes, source commit, application/DMG signing status, and `updatesEnabled`. Local metadata remains unpublished until the GitHub workflow publishes and verifies the assets. The command does not publish a GitHub release or modify the installed app. Only Developer ID mode uploads app/DMG artifacts to Apple for notarization. Both `--ad-hoc` and `--offline` perform no notarization upload; the flags are mutually exclusive because offline mode disables updates.

Build numbers are the greater of the current UTC Unix timestamp in seconds and one above all known build numbers. The local release history and an optional `--previous-release` metadata file provide the lower bound. The previous stable release must have a lower display version as well. This avoids repeated build numbers on clean CI runners or after a clock rollback. Keep local `release/*/release.json` records for successive local builds.

For development delivery, `./scripts/build-app.sh release --update` replaces and restarts an installation with the same bundle identifier. It preserves the installed version metadata when newer than the source defaults. A debug delivery keeps online checks disabled.

## GitHub Actions publication

A semver tag such as `v0.1.2` triggers the release workflow. Releases run serially across tags. The workflow:

1. requires the signing secret and verifies the previous stable release's version/build baseline;
2. rejects an equal or older display version and chooses a higher build number;
3. builds an ad-hoc application and unsigned, unnotarized DMG, then generates its signed update entry;
4. attaches the DMG, `appcast.xml`, `release.json`, and `SHA256SUMS.txt` to the GitHub Release;
5. verifies the public downloads and update signature, then builds a website artifact.

The previous-release check uses `publish-metadata.py --version-baseline`. It verifies the stable tag, metadata, public DMG size and SHA-256, and the Sparkle signature when online updates are enabled, then writes only `version` and `build` for the next release's lower bound. Historical ad-hoc or unnotarized releases can establish this baseline. Baseline output contains no website download metadata or appcast and cannot be used to advertise an installer.

The release and Pages workflows pass `--allow-ad-hoc` when exporting public metadata. That permits personal releases only when metadata explicitly reports ad-hoc application signing and no Apple notarization; contradictory Apple verification claims are rejected. Public downloads, SHA-256, feed consistency and Sparkle signatures are still verified. Without this option the exporter retains its Developer ID/notarization requirement. Personal releases are marked unnotarized on the home page, download page and GitHub Release. On first launch, macOS may require the user to allow the build through Privacy & Security after checking its source and checksum.

The Pages workflow runs after successful release workflow completion, stable release publishing/edits, website changes, or manual dispatch. It checks out `main`, resolves the latest stable release, verifies the public DMG's size, SHA-256 and EdDSA signature, validates the feed against that package, and deploys the feed alongside the website. Verification or build failures stop deployment. An older release without online-update metadata produces a valid empty feed during the transition.

Publication uses the repository's `GITHUB_TOKEN`; only the signing operation receives `SPARKLE_PRIVATE_KEY`. No personal access token, scheduled polling, or automatic metadata commit is needed. The public DMG and feed are checked without download credentials. The Pages verifier uses OpenSSL for public-key verification; on macOS it can use Homebrew OpenSSL when the system version lacks Ed25519 support.

## Release notes and signing boundary

`--notes` is required, including for previews. The script does not infer notes from commits or call an AI service. The tag workflow uses the version label for embedded notes and asks GitHub to generate the Release body; the website links to the full GitHub description.

Developer ID releases must pass nested Hardened Runtime, secure timestamps, Apple Accepted notarization, staple validation and Gatekeeper checks. `JOTWAY_NOTARY_PROFILE` names the pre-provisioned keychain profile. Any missing or failed condition stops that mode without falling back to ad-hoc. Release metadata reports `ad-hoc`, `developer-id` (verified against Apple's certificate requirement), or `certificate` for other certificate signatures such as local self-signed identities. Self-signed identities remain for local development. Personal distribution is an explicit `--ad-hoc` choice and records notarization, stapling, Gatekeeper acceptance and Developer ID distribution verification as false. Sparkle's EdDSA signature authenticates downloaded updates and does not claim Apple notarization. First installation remains a manual DMG installation subject to macOS's normal checks.

The non-sandboxed runtime, independent OCR sandbox, compatible update identity and source-preserving upgrade are specified in [Direct distribution runtime](../../openspec/specs/direct-distribution-runtime/spec.md).
