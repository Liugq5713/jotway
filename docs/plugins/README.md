# Optional capability and distribution

> Role: **Current**

“Plugin” in this repository means a compile-time optional capability boundary. Jotway does not currently download or execute third-party plugins at runtime, and actions are not called plugins.

## Distribution

All builds contain:

- the three-capability configuration owner, two typed invocation interfaces and per-flow text queues;
- DeepSeek and Moonshot OpenAI-compatible sources;
- all bundled launcher actions.

Debug and release use the same source tree and provider registration. No separate local-plugin build mode or additional source file is required.

The selected source is the saved deep preference, shared by answers/summaries and storage assistance. Fast remains separate. If a source is not registered in the current build, Jotway preserves the ID and reports it unavailable instead of silently switching credentials or providers.

## Boundaries

- Actions own user-facing destinations and execution.
- AI providers generate or transform text; they do not own routing or external writes.
- Provider keys remain local and are never stored in the SQLite launcher database.
- Optional provider failure must not turn a storage action into data loss.

`build-app.sh` packages the Jotway executable and Sparkle framework. Resources include the optional Codex user-script helper and its one-time installer. Codex CLI is installed and authenticated separately by the user; it is not bundled. There is no JavaScript runtime in the application bundle.

See [AI capability](ai.md), [provider implementation](ai-provider-implementation.md), and [provider onboarding](../development/ai-provider-onboarding.md).

Both debug and release also contain the independent Notes DashScope embedding client and statically built sqlite-vec v0.1.9 C target. The target registers per GRDB connection and shares system SQLite; no separately installed extension or extra runtime framework is required. History remains optional and off until configured in Apple Notes settings.
