# Adding an AI provider

> Role: **Reference**

Use this recipe for a compile-time provider with a fixed endpoint and model catalog. User-defined base URLs use PersonalModelConfiguration and the Claude/OpenAI-compatible adapters; see [provider implementation](../plugins/ai-provider-implementation.md). This recipe covers only compile-time sources.

## OpenAI-compatible provider

Prefer a thin configuration over `OpenAICompatible`:

1. Define a stable source ID, title, provider key, fixed HTTPS endpoint, model ID, and user disclosure.
2. Use `ModelConfiguration` key operations, backed by `APIKeyStore`, so every affected binding publishes a version.
3. Reject redirects so draft text and authorization headers cannot move to another host.
4. Return the provider/model identifier in the expected normalized form.
5. Register the text source in the model configuration catalog; keep `bundledAISources()` display order consistent. Bind it to fast or deep without changing business prompts.

Provider-specific request fields belong in the configuration's extra body, not in the shared transport.

Providers that require a local executable or inherited login context are not supported by the current package. Adding one requires a separately reviewed process, authentication, framing, timeout, cancellation, and packaging boundary; do not add an ad hoc helper to the shared provider path.

## Settings contract

A source declares its models, key URL, detail text, preference key, version string and frozen configuration closure. Settings use the central owner for key operations and capability status. Settings should derive UI from that declaration rather than switching on the provider ID.

If a saved source is absent from the current build, preserve the preference and report it unavailable. Never silently move a key or request to another provider.

## Verification

Before registering a source:

- compile debug and release configurations;
- exercise key save/remove and a fixed connection test;
- verify redirect rejection and request-size bounds;
- verify cancellation while queued and while running;
- verify empty output and mismatched/unknown model IDs are rejected;
- inspect runtime logs to confirm text, keys, and raw responses are absent.
