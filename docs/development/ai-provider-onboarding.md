# Adding an AI provider

> Role: **Reference**

Use this recipe for a compile-time provider with a fixed endpoint and model catalog. User-defined base URLs are a different security model and are outside this path.

## OpenAI-compatible provider

Prefer a thin configuration over `OpenAICompatible`:

1. Define a stable source ID, title, provider key, fixed HTTPS endpoint, model ID, and user disclosure.
2. Add key load/save/remove through `APIKeyStore`.
3. Reject redirects so draft text and authorization headers cannot move to another host.
4. Return the provider/model identifier in the expected normalized form.
5. Register the source in `bundledAISources()` in the intended display order.

Provider-specific request fields belong in the configuration's extra body, not in the shared transport.

Providers that require a local executable or inherited login context are not supported by the current package. Adding one requires a separately reviewed process, authentication, framing, timeout, cancellation, and packaging boundary; do not add an ad hoc helper to the shared provider path.

## Settings contract

A source declares its models, key URL, detail text, preference key, key operations, version string, and configuration closure. Settings should derive UI from that declaration rather than switching on the provider ID.

If a saved source is absent from the current build, preserve the preference and report it unavailable. Never silently move a key or request to another provider.

## Verification

Before registering a source:

- compile debug and release configurations;
- exercise key save/remove and a fixed connection test;
- verify redirect rejection and request-size bounds;
- verify cancellation while queued and while running;
- verify empty output and mismatched/unknown model IDs are rejected;
- inspect runtime logs to confirm text, keys, and raw responses are absent.
