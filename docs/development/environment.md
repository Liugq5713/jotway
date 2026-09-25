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

The XCTest suite requires full Xcode. If the active developer directory points to Command Line Tools, run tests with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`; this selects Xcode for that command without changing the system-wide toolchain.

`build-app.sh` packages and ad-hoc signs `Jotway.app`. `--update` replaces only an installation with the same bundle identifier, gracefully restarts it, and verifies the process. A different application at `/Applications/Jotway.app` stops installation without replacing it. Ordinary validation should avoid disturbing the user's running app.

## Application identity and storage

The product, SwiftPM executable, and module are all `Jotway`. The bundle identifier is `com.liuguangqi.jotway`.

- Application data: the app's Application Support directory under `Jotway/`, with `jotway.sqlite` and `Credentials/`.
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
