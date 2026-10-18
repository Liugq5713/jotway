# Optional capability and distribution

> Role: **Current**

“Plugin” in this repository means a compile-time optional capability boundary. Jotway does not currently download or execute third-party plugins at runtime, and actions are not called plugins.

## Distribution

All builds contain:

- the three-capability configuration owner, two typed invocation interfaces and per-flow text queues;
- Jotway AI activation, plus one personal model using native Claude Messages or an OpenAI-compatible endpoint;
- all bundled launcher actions.

Debug and release use the same source tree and provider registration. No separate local-plugin build mode or additional source file is required.

A stored Jotway AI code takes precedence for all text calls. Without a code, fast and deep share the single personal configuration; capability names only retain their business budgets and transport behavior. Legacy DeepSeek/Moonshot choices migrate to that configuration. Unknown or corrupt saved choices remain unavailable until repaired, rather than silently switching services.

## Boundaries

- Actions own user-facing destinations and execution.
- AI providers generate or transform text; they do not own routing or external writes.
- Provider keys remain local and are never stored in the SQLite launcher database. Jotway AI activation codes use the login Keychain; upstream and administrator keys never ship in the app.
- Optional provider failure must not turn a storage action into data loss.

`build-app.sh` packages the Jotway executable and Sparkle framework. Resources include the optional Codex user-script helper and its one-time installer. Codex CLI is installed and authenticated separately by the user; it is not bundled. There is no JavaScript runtime in the application bundle.

See [AI capability](ai.md), [provider implementation](ai-provider-implementation.md), and [provider onboarding](../development/ai-provider-onboarding.md).

Both debug and release retain statically built sqlite-vec only to migrate existing Notes caches: it registers with system SQLite so the retired vector tables can be dropped safely. No embedding client or vector-search capability is included.
