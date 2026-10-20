# AI capability

> Role: **Current**

Jotway uses optional models for Notes titles, daily grouping, today/weekly reviews and optional Instant Insight. Personal Agent is retired; its old preferences and local archives remain untouched.

Local application matching and ordinary input routing never call these models.

The lower-left Instant Insight button requires a configured active text model; the Today’s Review button requires a configured active text model. Unconfigured entries stay visible but disabled, with a hint to configure AI in AI Services. Losing the required configuration cancels pending generation and closes its temporary result. Automatic Instant Insight uses the same readiness gate.

## Jotway AI activation

Activation codes use `~/Library/Application Support/Jotway/Credentials/hostedAIActivation.json` (directory mode `0700`, file mode `0600`). Activation never reads, writes or deletes Keychain items. Codes previously stored in the Keychain must be entered again; there is no automatic Keychain migration.

AI Services temporarily hides its current-service card and Jotway AI activation and quota controls. The personal model form is directly visible without its heading or disclosure control. Existing activation codes and personal settings are preserved. A saved code takes precedence at the central invocation boundary: fast uses hosted DeepSeek Flash and deep uses hosted DeepSeek V4 Pro. The single personal model remains saved and inactive while any code is stored, even when the code is invalid, unavailable or depleted. A local credential read failure cannot route to personal credentials. Connection tests follow the same rule and retain the notice that they use Jotway AI quota.

The activation component remains in the source but is not mounted by settings, so opening AI Services does not refresh quota through that component. Hosted requests still refresh account metadata. Input and output tokens share the server-managed balance. The balance is a last-checked snapshot. Invalid or disabled responses clear it; network failures keep it with an unable-to-confirm status. Concurrent reads, cancellation and code changes cannot let older responses overwrite the latest credential state. Invalid, replaced or disabled codes and insufficient quota retain distinct errors in manual Instant Insight requests. Only fixed error categories cross that business UI boundary; unknown error text is never displayed. Code removal remains supported internally and restores the saved personal configuration for subsequent requests, but its settings control is temporarily hidden.

Hosted requests use the fixed Cloudflare service URL, an activation bearer code, and a fresh idempotency UUID. Each request selects one allowlisted, non-thinking model and sends at most 8,192 output tokens. Text requests have no backup model: an error never silently charges another service. The existing strict JSON/SSE model and completion checks remain in effect. Interrupted requests may retain held tokens until the service owner reconciles them. Hosted initial-title failures pause automatic title retries; ordinary original-text saving continues.

There is no registration, email, payment or account password in this flow. Anyone holding a code shares that code's quota. The app contains no administrator or upstream model credential. This service covers fast/deep text generation; embedding configuration and retrieval are removed.

## Instant Insight

The launcher owns one temporary draft response session. Each request freezes the text-model invocation, complete editor draft, UI language and shared effective prompt with its version. Manual and automatic requests use the same model input and answer rules; the trigger stays inside the app for scheduling, feedback and snapshot checks. One call returns answer or none and can combine translation, explanation, comparison, rewriting or other text help. The editable prompt replaces the bundled behavior rather than appending to it. Neither entry point silently adds Notes history, global background instructions, tools or retrieval. The model must state material uncertainty and cannot claim to check live facts.

The fixed kind/text protocol accepts answer with nonblank text or none with empty text. All answers share a 4,000-character / 16,000-UTF-8-byte limit without paragraph or question-count limits. Layout whitespace, code indentation and blank lines are preserved; CRLF and CR normalize to LF before checking the body. Other control characters, old semantic kinds, invalid structures, oversized or incomplete responses are rejected as a whole. The encoded request, including the effective prompt, and the raw response each have a 65,536-byte limit. The total deadline is 20 seconds including queueing; ordinary output allows 8,192 tokens and thinking models 16,384. Validation does not make another model call or prove factual quality.

Both sources render the same limited Markdown: paragraphs, headings, flat lists, emphasis, inline/fenced code and simple pipe tables. Code preserves whitespace; unsupported syntax remains readable as literal text. Links display their name and address without an action; images and HTML never load or execute. The read-only card keeps its snapshot label, fixed accessibility announcement and 180 pt scroll region, with horizontal scrolling inside wide code/table blocks. Results never enter the draft, action input or local operation text.

Automatic requests retain their one-second debounce, latest pending candidate, close suppression and silent loading/empty/failure handling. Manual requests retain visible feedback and their original draft snapshot while writing continues; automatic results require matching current text. Changing the effective prompt cancels both sources and clears the result; old callbacks cannot return. Saving alone does not request or requeue the same text and does not reset close suppression. Diagnostics keep the internal `draftThinkingPrompt` purpose with identifiers, counts and outcome codes, with content receivers disabled. See [Instant Insight](../../openspec/specs/draft-thinking-prompts/spec.md) for configuration, privacy and lifetime boundaries.

## Notes original saves

Notes saves the complete frozen original and resolves its separate title through the fast capability. It creates no AI Insights or Related Content and does not call the deep capability for saving. There is no supplement preparation, five-minute wait, post-save refresh or startup replay.

The former supplement controls are removed. Old enable, prompt and rewrite preferences remain stored but inactive; the legacy prompt field survives configuration round trips without contributing to active version hashes. General instructions and retained review preferences still apply to their own consumers. Automatic fixed and AI tags remain paused. Titles, daily classification, reviews and temporary draft responses keep their independent rules.

Verified legacy generated text and existing coverage metadata survive permitted same-day appends and title updates. Markup is retained when verifiable; otherwise boundary-verified plaintext survives without rebuilding links. No cleanup, new stale notice or historical rewrite is performed. See [Notes AI assistance](../../openspec/specs/notes-ai-assistance/spec.md).

## Daily Notes grouping

Notes has an independent, default-on daily grouping switch; an explicitly saved off value remains off. Classification uses an independent fast invocation: hosted Flash or the shared personal model. Known official DeepSeek models disable thinking; known Kimi Code models use the explicitly declared thinking/output budget. Generic services receive the ordinary output budget and a JSON instruction; existing business validation remains required. No history index is required. The request contains the new original and complete original entries from verified managed notes in today's destination folder. Old generated content and retrieved history are excluded. Settings discloses which service receives originals and bills the request.

Classification prefers the same project across different issues and opinions; without a named project it uses a natural topic. The application checks the returned model, response shape, title bounds and candidate ID. The encoded request has a 128 KiB limit and classification has a 120-second deadline including its queue; candidate preparation and folder queueing have a separate 180-second budget. Missing configuration, ambiguous/invalid responses, model mismatch, budget overflow or timeout causes an independent save; late decisions never move saved content. These checks do not prove semantic classification quality.

The original is saved and confirmed through the existing FIFO and final readback. No generated-content request follows confirmation. The legacy `pending.refresh` kind remains decodable for read-only reconciliation; an unresolved operation continues to protect its note from further writes.

Disabling grouping restores ordinary per-submission creation. Independent titles and reviews remain available; legacy supplement preferences have no runtime effect.

## Today and weekly reviews

The launcher has one Today’s Review entry that opens today’s detail panel; the panel offers today and weekly periods, with no monthly option. Reopening from the footer always starts with today. NotesReview reads authorized Notes originals on demand, freezes the source metadata and deep invocation, then exposes a temporary readable preview separately from its completed summary. The view uses those frozen dates, source count and coverage while generation continues. Safely decoded overview text can appear as it arrives; complete validated themes and questions follow. The lower panel keeps a stable scrolling viewport and a generating label until final validation replaces the preview.

Each request owns its preview. Closing the review or hiding the panel clears only the display; the request keeps running while Jotway is open. Reopening the same period restores its current progress or valid completed cache without starting another request. A today request from a different local date boundary is replaced when reopened. Background progress and completion never open the panel or take focus. Switching periods cancels the previous request; range, availability or deep configuration changes invalidate affected results. A failed stream ends generation without a background retry. Only a completed valid response enters the independent period cache. Reviews remain read-only and never change the draft or Notes. Exact limits, cancellation and cache behavior are defined in [Notes review](../../openspec/specs/notes-review/spec.md).

## General provider configuration

`ModelConfiguration` resolves hosted-code priority before consulting personal preferences. Personal mode has one service type, HTTPS Base URL, model ID and API key, shared by fast and deep. Claude uses native Messages; OpenAI-compatible services use Chat Completions. The user supplies a base URL, without the final `/messages` or `/chat/completions` suffix. HTTPS addresses cannot contain credentials, query strings or fragments; requests refuse redirects. Changing the service or address requires re-entering the key to avoid forwarding an old secret to another endpoint.

DeepSeek, Kimi, OpenAI and Claude presets supply their official address, protocol and key-page link; custom services keep editable settings. Presets are inferred from the saved destination without adding stored provider fields. Explicit model discovery uses the personal form's address and entered key, or the saved personal key only for the same normalized address and protocol. It never uses the activation code or sends draft text. The ephemeral directory request refuses redirects, has a 20-second resource deadline and a 2 MB response limit, and displays at most 1000 models from the first page. Partial or empty lists are identified; failures use fixed messages. Listing does not prove text-generation support. Manual model IDs remain available, and discovery never changes the selected ID automatically.

The versioned `plugin.ai.personalModel.v1` preference stores metadata only. Personal keys use the existing restricted credential store. Legacy deep selections migrate to a single configuration using the existing key; old fast/fallback preferences remain stored but inactive. If older activation replaced both bindings, migration recovers an explicitly saved personal source or an existing DeepSeek key, then Moonshot key. Unknown/corrupt preferences remain unavailable until explicitly repaired. Opening settings and migration send no model requests.

Each logical call freezes one service, model, endpoint and credential. There is no automatic provider fallback. Fast/deep retain 120/300-second total deadlines including queueing, constrained by shorter business deadlines. Changes invalidate affected work; independent flows keep separate queues. Existing same-day personal-title recovery remains on that service; hosted failures pause its automatic retries. Model tests use fixed text through the active route, with deep streaming and a 30-second deadline. Unsaved edits disable tests. Edits, effective configuration changes and view exit discard stale test results.

Native Claude sends system instructions separately, reads only text blocks, ignores thinking content and requires a complete `end_turn` result. SSE must complete the block lifecycle and `message_stop`. Generic OpenAI-compatible JSON tasks use an explicit JSON instruction rather than assuming every service supports `response_format`; business parsers validate all results. Known official DeepSeek/Kimi configurations retain their protocol-specific fields. Personal model aliases may resolve to a concrete returned ID, which must remain consistent within a stream. Hosted calls retain exact-model matching. Missing identities, truncation, tool calls and invalid business output fail the request.

## Safety boundaries

- Requests have a bounded encoded size.
- Calls within one frozen text invocation are serialized; independent flows use separate actors. Fast invocations do not wait behind a deep answer.
- A valid returned model identity is required. Hosted mismatches and identity changes within a personal stream discard the result.
- Cancellation propagates through queued and running work.
- Runtime logs record bounded stages, identifiers, outcomes, and timing without draft text or keys.

Provider transport details are in [AI provider implementation](ai-provider-implementation.md).


## Diagnostics

Logical call and attempt identities connect capability, request role, requested/actual model, bounded failure class, elapsed time and final outcome. Runtime logs contain no text or keys. The opt-in `ModelDiagnostics` content receiver remains available, but Notes does not install one. No Personal Agent session is created or updated. Existing archives and historical metadata remain untouched.
