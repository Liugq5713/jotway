# AI provider implementation

> Role: **Reference**

## Registration

`bundledAISources()` defines the sources visible in Settings. DeepSeek and Moonshot use `OpenAICompatible`. `installPlugins(into:)` installs the shared provider and connection-test hook.

## Request lifecycle

`AIProviderPlugin` is an actor and allows one provider request at a time.

1. Capture the selected source/model and manual configuration on the main actor.
2. Build a bounded request with fixed rules, optional user Instructions, and task content.
3. Queue behind any active request.
4. Perform the provider call with cancellation and runtime-log context.
5. Validate non-empty output and the observed model identifier.
6. Return text or a bounded typed failure.

Queued requests keep the configuration snapshot taken before queuing. A later settings change cannot redirect an in-flight request to another provider.

## Direct providers

DeepSeek and Moonshot are thin configurations over the OpenAI-compatible transport. Each declares its HTTPS endpoint, model ID, key storage key, user-facing disclosure, and any provider-specific body fields.

## Failure policy

Provider failures are meaningful to callers, but storage action processors deliberately catch them and return the original text. A connection test surfaces the failure because its purpose is to diagnose configuration.
