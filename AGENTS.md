# Repository Guidelines

## Context and Documentation

Before starting work, read [CONTEXT.md](CONTEXT.md) and use its terminology. For behavior changes, follow the relevant current specification from [docs/jotway.md](docs/jotway.md). Inspect `git status` and preserve existing uncommitted work.

Documentation has four roles: **Current** describes shipped behavior, **Work** describes one active change, **Reference** records reusable external or operational facts, and **Decision** explains a durable trade-off. Keep one role per document. Merge completed behavior into Current docs, then delete the Work document; Git preserves history. Verification logs belong in commits or task handoffs rather than Current docs.

## Project Structure

Jotway is a native macOS app using SwiftUI and AppKit.

- `Sources/App/`: application state, menus, settings, onboarding, and updates.
- `Sources/Actions/`: the action contract, registry, text pipeline, previews, and bundled actions.
- `Sources/Features/Editor/` and `Sources/Features/Launcher/`: editor/Markdown behavior plus launcher search and feedback mapping.
- `Sources/Window/`: quick panel presentation, focus, routing, and execution flow.
- `Sources/Data/`: GRDB schema plus application usage, intent feedback, and intent corrections.
- `Sources/Integrations/` and `Sources/Support/`: external APIs and macOS service adapters.
- `Sources/Plugins/`: optional AI providers and their registration.
- `Tests/JotwayTests/`: application tests; `Resources/`: metadata, icons, and entitlements.
- `Vendor/KeyboardShortcuts/`: locally patched dependency.

The inbox, records, cards, Summary, completion/export flow, and retired destination-specific subsystems have been removed. Jotway starts with its own database schema and storage locations; it does not import another application’s data or credentials. For plugin packaging or release scope, follow [the plugin distribution convention](docs/plugins/README.md#distribution).

## Build, Test, and Development Commands

Use Swift 6.2 with the macOS 26 SDK. The deployment target is macOS 15; SwiftPM is the normal development workflow.

- `swift build`: compile the application.
- `swift test`: run application tests.
- `./scripts/build-app.sh`: build, package, and ad-hoc sign `Jotway.app`; append `release` for a release build.
- `./scripts/build-app.sh --update`: build and replace the installed app directly, then restart and verify its process.
- `swift test --package-path Vendor/KeyboardShortcuts`: run dependency tests after changing vendored code.

For delivery, `./scripts/build-app.sh --update` replaces and restarts only an installation with the same bundle identifier. When the destination belongs to another application, keep it intact and report the conflict. Documentation, tests, and tooling changes do not require an app update.

## Coding Style

Use four-space indentation, `UpperCamelCase` types, and `lowerCamelCase` members. Name files after their primary type; preserve surrounding style in vendored files. Keep UI mutations on `@MainActor`. Prefer existing functions and types; introduce abstractions only for demonstrated reuse. No repository-wide formatter or linter is configured.

## Testing

After code changes, verify the affected behavior with a build, type check, existing test, command-line call, or minimal real use. Do not add tests unless the user explicitly asks. Isolate persistence, clipboard, and preferences checks with in-memory repositories, unique pasteboards, and separate defaults suites.

By default, do not launch or drive `Jotway.app`; it disrupts the user's computer. Prefer `swift build` and non-UI checks. Delivery-related restarts follow the scope above. For focus return, Chinese input composition, or other real-window behavior, describe manual verification unless the user explicitly requests automated UI verification.

## Commits and Pull Requests

Use short `<type>: <summary>` subjects (`feat:`, `fix:`, `chore:`) and keep commits focused. PRs should explain the problem, resulting behavior, validation, and remaining limitations. Keep generated build products untracked.
