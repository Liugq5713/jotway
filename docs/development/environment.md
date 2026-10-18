# Development environment

> Role: **Current**

## Toolchain

- Swift 6.2
- macOS 26 SDK
- macOS 15 deployment target
- Swift Package Manager
- Locally patched `Vendor/KeyboardShortcuts`

## Common commands

```bash
swift build
swift test
swift test --package-path Vendor/KeyboardShortcuts
./scripts/build-app.sh
./scripts/build-app.sh release
./scripts/build-app.sh --update
```

Ordinary app builds support Command Line Tools with the required Swift version and SDK. Settings environment values use explicit `EnvironmentKey` declarations rather than `@Entry`, so they do not require Xcode's SwiftUI macro plugin.

The XCTest suite requires full Xcode. If the active developer directory points to Command Line Tools, run tests with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`; this selects Xcode for that command without changing the system-wide toolchain.

`build-app.sh` packages and signs `Jotway.app`. `--update` replaces only an installation with the same bundle identifier, gracefully restarts it, and verifies the process. A different application at `/Applications/Jotway.app` stops installation without replacing it. Ordinary validation should avoid disturbing the user's running app.

### Stable local signing

Both `build-app.sh` and `release.py` use `scripts/code_signing.py` for the app and nested Sparkle components. Select a signing identity with `JOTWAY_SIGNING_IDENTITY`, or save its SHA-1 certificate fingerprint as the only line in the ignored `.secrets/signing-identity` file. The environment variable takes precedence. An unconfigured checkout retains ad-hoc signing; an explicitly configured certificate that is missing, expired, untrusted, or ambiguous stops packaging instead of falling back. `-` explicitly selects ad-hoc signing.

For local identities without an Apple Team ID (ad-hoc or self-signed), packaging keeps Hardened Runtime and generates a main-app-only `com.apple.security.cs.disable-library-validation` entitlement so macOS can load the bundled Sparkle framework. The shared entitlement file and OCR helper sandbox stay unchanged. Apple team identities keep library validation enabled, and public distribution rejects the local exception. See [Sparkle's development signing requirements](https://sparkle-project.org/documentation/#1-add-the-sparkle-framework-to-your-project) and the [runtime specification](../../openspec/specs/direct-distribution-runtime/spec.md).

Inspect available identities and the selected identity without building or using a private key:

```bash
security find-identity -v -p codesigning
python3 scripts/code_signing.py identity
```

The certificate and its private key must already be available to `codesign` in the macOS keychain. The scripts do not create, import, export, or change trust for certificates. Use a dedicated, persistent self-signed code-signing certificate for local development, or an Apple-issued identity appropriate to the distribution channel. Keep the same identity across builds; the fingerprint configuration does not contain the private key. [Apple's signing guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html) describes identity creation and the limits of self-signed certificates.

Ad-hoc signatures identify individual builds. macOS permission services can use the application's designated requirement to recognize it across updates, so a stable certificate addresses reauthorization caused by changing ad-hoc identities. The first migration may still require authorization. `--update` checks that certificate-signed old and new apps satisfy each other's designated requirement before staging or quitting the installed app; an incompatible certificate or ad-hoc replacement stops the update. It does not reset permissions or guarantee that every system permission will persist. See [Apple TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).

All update sources must use a compatible identity. A locally configured certificate does not configure GitHub Actions or change existing public downloads. Debug builds disable online updates; when testing a fixed local identity, use debug builds or an offline release until the distribution channel uses the intended certificate too.

## OpenSpec planning

OpenSpec uses the upstream `spec-driven` schema with project context and artifact rules in [openspec/config.yaml](../../openspec/config.yaml). It generates Chinese planning content while preserving the structural headings required by the official templates.

Install the CLI with Node.js 20.19.0 or later, then initialize the Codex integration from the repository root:

```bash
npm install -g @fission-ai/openspec@latest
openspec init --tools codex --profile core --language zh-CN --no-animation
```

The generated official skills live in `.agents/skills/openspec-*`, which this repository ignores. Re-run initialization for another checkout; keep customization in the project config. Use `openspec update` to refresh generated skills after upgrading the CLI.

In Codex, invoke `openspec-propose` with a concrete change description to draft a plan for review. The five planning topics map to proposal (background/goals), design (module changes/shared decisions), specs (acceptance behavior), and tasks (execution/handoff). Implementation and Multica dispatch follow the user's requested scope.

The current rollout covers planning and handoff. Existing Current documents remain authoritative; adopting OpenSpec sync/archive requires first reconciling its persistent archive with the repository's rule to remove completed Work documents. Project context records this boundary but does not change the CLI's archive operations.

## Application identity and storage

The product, SwiftPM executable, and module are all `Jotway`. The bundle identifier is `com.liuguangqi.jotway`.

- Application data: the account home’s `Library/Application Support/Jotway/`, with `jotway.sqlite` and `Credentials/`; the bundle identifier remains `com.liuguangqi.jotway`.
- Preferences and permissions: the Jotway application identity.
- Runtime logs: the app's Library directory under `Logs/Jotway/`.
- Startup timing: opt in with `JOTWAY_STARTUP_TIMING=1`.

A fresh installation creates its own database and starts onboarding. It does not import another application's preferences, database, or keychain entries. Configure destinations and API keys in Jotway settings. Online updates remain disabled until a new feed and signing configuration are supplied; see [App updates](../product/updates.md).

## AI sources

Debug and release compile the same source tree, including the AI provider contract and direct DeepSeek and Moonshot transports. No private plugin source, separate build flag, or helper executable is required.

## Interface resources

The shipped interface language is English. SwiftPM processes `Sources/Resources/en.lproj` with `en` as the package's default localization. App-owned copy is looked up by semantic key from the package resource bundle, leaving a standard `.lproj` extension point for a future additional language without adding language-dependent business state.

Permission-purpose strings are also shipped in English. `build-app.sh` copies `InfoPlist.strings` into the main application resources because macOS reads permission copy from the app bundle rather than the SwiftPM resource bundle. The packaging step removes non-English localizations from nested dependency bundles, while retaining `Base.lproj` resources when present, so third-party controls cannot independently follow a non-English system language. The main `Info.plist` declares only English as a shipped localization.

## Generated products

`.build/`, packaged applications, exported logs, and local receipts are build products rather than source documentation. Do not add their paths, timings, PIDs, or hashes to Current docs.

## Storage recovery

Before normal startup, the non-sandboxed app migrates its own old `Library/Containers/com.liuguangqi.jotway/Data/Library/Application Support/Jotway` and persistent preference domain. The staged copy and journal live under `Library/Application Support/.Jotway-migration`; source files remain unchanged. See [Direct distribution runtime](../../openspec/specs/direct-distribution-runtime/spec.md).

If startup shows recovery, close other Jotway instances and retry. If access is unavailable, choose your own `com.liuguangqi.jotway` container through the recovery button and retry. Conflicting roots or failed integrity checks stop business startup and preserve both locations; they require resolving the stated conflict before another retry. Do not delete either root to force startup.

After successful migration, the direct location owns new writes and the original container is only the earlier snapshot. Keep both and back up or explicitly migrate new content before returning to an older build; no automatic reverse migration occurs. Notes, Chrome and Accessibility remain separate permissions. The app does not reset TCC or promise that identity continuity prevents every reauthorization request.

## Public distribution gate

Local `build-app.sh` packages are development artifacts, even when a certificate is selected. Public `release.py` requires an available fixed Developer ID identity and a pre-provisioned `JOTWAY_NOTARY_PROFILE` keychain profile. It verifies signed entitlements, nested runtime and timestamps, submits the app and DMG to Apple, staples and validates them, and requires Gatekeeper acceptance before generating public metadata. Missing conditions fail closed. `--offline` retains an explicitly non-public development package. See [Updates](../product/updates.md).
