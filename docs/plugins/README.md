# Optional capability and distribution

> Role: **Current**

“Plugin” in this repository means a compile-time optional capability boundary. Jotway does not currently download or execute third-party plugins at runtime, and actions are not called plugins.

## Distribution

All builds contain:

- the `AIProviderPlugin` contract and queue;
- DeepSeek and Moonshot OpenAI-compatible sources;
- all bundled launcher actions.

Debug and release use the same source tree and provider registration. No separate local-plugin build mode or additional source file is required.

The selected source is a saved preference. If a source is not registered in the current build, Jotway preserves the ID and reports it unavailable instead of silently switching credentials or providers.

## Boundaries

- Actions own user-facing destinations and execution.
- AI providers generate or transform text; they do not own routing or external writes.
- Jev is a separate intent-recognition service and has its own key/settings.
- Provider keys remain local and are never stored in the SQLite launcher database.
- Optional provider failure must not turn a storage action into data loss.

`build-app.sh` packages the Jotway executable and Sparkle framework. There is no external action helper or JavaScript runtime in the application bundle.

See [AI capability](ai.md), [provider implementation](ai-provider-implementation.md), and [provider onboarding](../development/ai-provider-onboarding.md).
