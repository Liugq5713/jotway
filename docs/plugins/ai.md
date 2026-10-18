# AI capability

> Role: **Current**

Jotway uses optional models for Notes titles, daily grouping, supplements, today/weekly reviews and optional draft thinking prompts. Personal Agent is retired; its old preferences and local archives remain untouched.

Local application matching and ordinary input routing never call these models.

The lower-left thinking-prompt button requires a configured active text model; the Today’s Review button requires a configured active text model. Unconfigured entries stay visible but disabled, with a hint to configure AI in AI Services. Losing the required configuration cancels pending generation and closes its temporary result. Automatic thinking prompts use the same readiness gate.

## Jotway AI activation

Activation codes use `~/Library/Application Support/Jotway/Credentials/hostedAIActivation.json` (directory mode `0700`, file mode `0600`). Activation never reads, writes or deletes Keychain items. Codes previously stored in the Keychain must be entered again; there is no automatic Keychain migration.

AI Services starts with Jotway AI activation. A validated code is stored in Jotway's local credential directory with access restricted to the current user and takes precedence at the central invocation boundary: fast uses hosted DeepSeek Flash and deep uses hosted DeepSeek V4 Pro. The single personal model remains saved and inactive while any code is stored, even when the code is invalid, unavailable or depleted. A local credential read failure cannot route to personal credentials. Connection tests follow the same rule. Removing the code resumes the saved personal model for subsequent requests; the removal UI explains this.
The activated card shows the service status, latest available token balance and any held tokens; Change Code reveals the replacement form. A short next step points to Quick Entry and its thinking-prompt icon. Opening the card, choosing Refresh Quota, or completing a hosted request fetches account metadata without calling another model. Input and output tokens share the server-managed balance. The balance is a last-checked snapshot. Invalid or disabled responses clear it; network failures keep it with an unable-to-confirm status. Concurrent reads, cancellation and code changes cannot let older responses overwrite the latest credential state. Invalid, replaced or disabled codes and insufficient quota have distinct errors in settings and manual thinking prompts, with a link back to Jotway AI settings. Only fixed error categories cross that business UI boundary; unknown error text is never displayed. Remove Code leaves the server balance intact and restores the saved personal configuration for subsequent requests.

Hosted requests use the fixed Cloudflare service URL, an activation bearer code, and a fresh idempotency UUID. Each request selects one allowlisted, non-thinking model and sends at most 8,192 output tokens. Text requests have no backup model: an error never silently charges another service. The existing strict JSON/SSE model and completion checks remain in effect. Interrupted requests may retain held tokens until the service owner reconciles them. Hosted initial-title failures pause automatic title retries; ordinary original-text saving continues.

There is no registration, email, payment or account password in this flow. Anyone holding a code shares that code's quota. The app contains no administrator or upstream model credential. This service covers fast/deep text generation; embedding configuration and retrieval are removed.

## Draft thinking prompts

The launcher owns a separate temporary prompt session. Each request freezes a fresh fast invocation and the complete editor draft; it does not use Notes retrieval, the supplement preference or the Notes serial work queues. The generator defaults to silence and returns one validated plain-text scaffold only for a concrete gap that can help advance the user’s thinking; otherwise it returns a valid empty result. Routine notes and complete thoughts do not need a follow-up. Failures remain safe states. Its independent deadline includes model queueing. Each call uses one model; business output validation does not call another provider.

Manual requests use a snapshot. The opt-in automatic preference adds its own debounce and one latest pending candidate; stale automatic responses cannot overwrite new text. Automatic requests display only validated nonempty prompts; loading, empty results and failures keep the panel closed. Manual requests retain explicit loading, empty and failure feedback. Results live only in the lower panel and never enter action input or local operation text. Diagnostics use the `draftThinkingPrompt` purpose with identifiers, counts and outcome codes, and explicitly disable content receivers. See [Thinking prompts](../../openspec/specs/draft-thinking-prompts/spec.md) for limits and protected states.

## Action text processing

Notes supplements use the centrally resolved `deep` invocation: hosted Pro when a code exists, otherwise the single personal model:

- Notes uses a dedicated supplement processor. The exact original draft remains owned by the application; the model returns a bounded structured result containing zero to three useful analyses or suggestions and zero to five historical associations. The application appends valid content under “AI 洞察” and constructs the final HTML itself.

Each action keeps its independent enable preference. Notes reuses its existing on/off value but stores supplement preferences separately from legacy rewrite styles, which remain stored and inactive. The default remains enabled when no value exists. Notes preserves original text, first line, blank lines, spacing, tabs, indentation and literal text syntax regardless of model output. Automatic fixed and AI tags are paused; saved preferences and user-written original tags are retained. Generated tag and category metadata is ignored and never appended to the original.

Missing key, network error, timeout, empty response or invalid output produces no Notes supplement; the original is still saved. No fallback copy is appended. The deep invocation shares one five-minute deadline including queueing; retrieval consumes the existing Notes preparation deadline before generation receives its remaining time. Submission cancellation prevents a write; optional service cancellation only skips the supplement.

Deep supplement requests receive streamed content internally. Notes waits for the complete response and existing business validation before adopting a supplement once; partial content never reaches Notes. A failed attempt ends generation without another model request or repeated original write. See [Notes AI assistance](../../openspec/specs/notes-ai-assistance/spec.md) for the adoption and original-text contract.

With daily grouping disabled, Notes accepts confirmation and hides the panel immediately, then runs supplementation in the background with a shared five-minute deadline. It does not prewarm these services while typing. Failure or timeout skips optional content without waiting for cancellation to finish; late results are ignored. This ordinary path uses one result and one create request per accepted confirmation, with no later append. Custom supplement preferences cannot authorize replacing the original, inventing user background, or implying that external information was searched or verified. Questions in the draft can be answered in the separate supplement; instructions embedded in drafts or sources do not authorize rewriting, rule changes or external actions. Historical proposals are not proof that work remains unfinished; uncertainty and conflicting completion evidence must be stated.

## Daily Notes grouping

Notes has an independent, default-on daily grouping switch; an explicitly saved off value remains off. Classification uses an independent fast invocation: hosted Flash or the shared personal model. Known official DeepSeek models disable thinking; known Kimi Code models use the explicitly declared thinking/output budget. Generic services receive the ordinary output budget and a JSON instruction; existing business validation remains required. No history index is required. The request contains the new original and complete original entries from verified managed notes in today's destination folder. Old generated content and retrieved history are excluded. Settings discloses which service receives originals and bills the request.

Classification prefers the same project across different issues and opinions; without a named project it uses a natural topic. The application checks the returned model, response shape, title bounds and candidate ID. The encoded request has a 128 KiB limit and classification has a 120-second deadline including its queue; candidate preparation and folder queueing have a separate 180-second budget. Missing configuration, ambiguous/invalid responses, model mismatch, budget overflow or timeout causes an independent save; late decisions never move saved content. These checks do not prove semantic classification quality.

The original is confirmed first. With Add Extra Ideas enabled, the frozen deep invocation then processes the complete accumulated originals under a separate 300-second deadline including preparation and queueing. A bounded history query includes the latest entry and excludes the target note from sources. Only the latest valid same-day revision can replace the shared generated sections. Old results retain a coverage-time notice until replacement; valid empty results remove them. Failure leaves the original saved. Existing tolerant parsing keeps valid entries and skips invalid siblings.

Disabling assistance cancels refreshes and skips its retrieval, while fast grouping remains available. The next managed original write removes old generated content; toggling alone does not rewrite Notes. Disabling grouping restores ordinary per-submission creation without changing the assistance preference.

## Today and weekly reviews

The launcher has one Today’s Review entry that opens today’s detail panel; the panel offers today and weekly periods, with no monthly option. Reopening from the footer always starts with today. NotesReview reads authorized Notes originals on demand, freezes the source metadata and deep invocation, then exposes a temporary readable preview separately from its completed summary. The view uses those frozen dates, source count and coverage while generation continues. Safely decoded overview text can appear as it arrives; complete validated themes and questions follow. The lower panel keeps a stable scrolling viewport and a generating label until final validation replaces the preview.

Each request owns its preview. A failed stream ends generation; closing the review or leaving its surface cancels pending updates. Range, availability or deep configuration changes invalidate affected results. Only a completed valid response enters the independent period cache. Reviews remain read-only and never change the draft or Notes. Exact limits, cancellation and cache behavior are defined in [Notes review](../../openspec/specs/notes-review/spec.md).

## General provider configuration

`ModelConfiguration` resolves hosted-code priority before consulting personal preferences. Personal mode has one service type, HTTPS Base URL, model ID and API key, shared by fast and deep. Claude uses native Messages; OpenAI-compatible services use Chat Completions. The user supplies a base URL, without the final `/messages` or `/chat/completions` suffix. HTTPS addresses cannot contain credentials, query strings or fragments; requests refuse redirects. Changing the service or address requires re-entering the key to avoid forwarding an old secret to another endpoint.

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
