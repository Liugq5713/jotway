# AI capability

> Role: **Current**

Jotway uses optional models for Notes titles, daily grouping, supplements, weekly/monthly reviews and optional draft thinking prompts. Personal Agent is retired; its old preferences and local archives remain untouched.

Local application matching and ordinary input routing never call these models.

## Draft thinking prompts

The launcher owns a separate temporary prompt session. Each request freezes a fresh fast invocation and the complete editor draft; it does not use Notes retrieval, the supplement preference or the Notes serial work queues. The generator returns one validated plain-text scaffold, a valid empty result or a safe failure state. Its independent deadline includes model queueing. Model fallback follows the existing chain policy, while business output validation does not call another provider.

Manual requests use a snapshot. The opt-in automatic preference adds its own debounce and one latest pending candidate; stale automatic responses cannot overwrite new text. Results live only in the lower panel and never enter action input or local operation text. Diagnostics use the `draftThinkingPrompt` purpose with identifiers, counts and outcome codes, and explicitly disable content receivers. See [Thinking prompts](../../openspec/specs/draft-thinking-prompts/spec.md) for limits and protected states.

## Action text processing

Notes supplements use the `deep` primary/fallback chain selected in Writing Help, defaulting to DeepSeek Pro → Kimi Code:

- Notes uses a dedicated supplement processor. The exact original draft remains owned by the application; the model returns a bounded structured result containing zero to three useful analyses or suggestions and zero to five historical associations. The application appends valid content under “AI 洞察” and constructs the final HTML itself.

Each action keeps its independent enable preference. Notes reuses its existing on/off value but stores supplement preferences separately from legacy rewrite styles, which remain stored and inactive. The default remains enabled when no value exists. Notes preserves original text, first line, blank lines, spacing, tabs, indentation and literal text syntax regardless of model output. Automatic fixed and AI tags are paused; saved preferences and user-written original tags are retained. Generated tag and category metadata is ignored and never appended to the original.

Missing key, network error, timeout, empty response or invalid output produces no Notes supplement; the original is still saved. No fallback copy is appended. The deep chain shares one five-minute deadline including queueing; retrieval consumes the existing Notes preparation deadline before generation receives its remaining time. Submission cancellation prevents a write; optional service cancellation only skips the supplement.

Deep supplement requests receive streamed content internally. Notes waits for the complete response and existing business validation before adopting a supplement once; partial content never reaches Notes. A failed primary attempt can pass control to the frozen fallback chain without repeating the original write. See [Notes AI assistance](../../openspec/specs/notes-ai-assistance/spec.md) for the adoption and original-text contract.

With daily grouping disabled, Notes accepts confirmation and hides the panel immediately, then runs related-history retrieval and supplementation in the background with a shared five-minute deadline. It does not prewarm these services while typing. Failure or timeout skips optional content without waiting for cancellation to finish; late results are ignored. This ordinary path uses one result and one create request per accepted confirmation, with no later append. Custom supplement preferences cannot authorize replacing the original, inventing user background, or implying that external information was searched or verified. Questions in the draft can be answered in the separate supplement; instructions embedded in drafts or sources do not authorize rewriting, rule changes or external actions. Historical proposals are not proof that work remains unfinished; uncertainty and conflicting completion evidence must be stated.

## Daily Notes grouping

Notes has an independent, default-on daily grouping switch; an explicitly saved off value remains off. Classification uses the fast chain (Flash → Kimi Code Highspeed by default), in an independent flow. Flash uses thinking disabled and 512 tokens; Kimi uses an explicitly declared 16,384-token thinking/output budget. Both request JSON. No history index is required. The request contains the new original and complete original entries from verified managed notes in today's destination folder. Old generated content and retrieved history are excluded. Settings discloses that both configured providers may receive the same originals and bill separately.

Classification prefers the same project across different issues and opinions; without a named project it uses a natural topic. The application checks the returned model, response shape, title bounds and candidate ID. The encoded request has a 128 KiB limit and classification has a 120-second deadline including its queue; candidate preparation and folder queueing have a separate 180-second budget. Missing configuration, ambiguous/invalid responses, model mismatch, budget overflow or timeout causes an independent save; late decisions never move saved content. These checks do not prove semantic classification quality.

The original is confirmed first. With Add Extra Ideas enabled, the frozen deep chain then processes the complete accumulated originals under a separate 300-second deadline including preparation and queueing. A bounded history query includes the latest entry and excludes the target note from sources. Only the latest valid same-day revision can replace the shared generated sections. Old results retain a coverage-time notice until replacement; valid empty results remove them. Failure leaves the original saved. Existing tolerant parsing keeps valid entries and skips invalid siblings.

Disabling assistance cancels refreshes and skips its retrieval, while fast grouping remains available. The next managed original write removes old generated content; toggling alone does not rewrite Notes. Disabling grouping restores ordinary per-submission creation without changing the assistance preference.

## Weekly and monthly reviews

The launcher requests a review only when the user opens its weekly or monthly surface. NotesReview reads the existing authorized index, freezes the source metadata and deep invocation, then exposes a temporary readable preview separately from its completed summary. The view uses those frozen dates, source count and coverage while generation continues. Safely decoded overview text can appear as it arrives; complete validated themes and questions follow. The lower panel keeps a stable scrolling viewport and a generating label until final validation replaces the preview.

Each model attempt owns its preview. Starting a fallback clears the primary's content; closing the review or leaving its surface cancels pending updates. Range, availability or deep configuration changes invalidate affected results. Only a completed valid response enters the independent period cache. Reviews remain read-only and never change the draft or Notes. Exact limits, cancellation and cache behavior are defined in [Notes review](../../openspec/specs/notes-review/spec.md).

## General provider configuration

`ModelConfiguration`, owned by AppState, holds fast/deep primary and optional fallback bindings plus the independent embedding binding. Fast defaults to Flash → Kimi Code Highspeed; deep defaults to Pro → Kimi Code. A chain can be reversed atomically or use None. DeepSeek and Moonshot each share one key across their models. Only chains referencing a changed credential receive a different version.

Versioned `plugin.ai.textBindings.v1` stores the full chains. Migration preserves an explicit legacy deep source/model, unknown choices and old preference values. An unreadable new value remains stored and unavailable until the user repairs it. Opening settings or swapping models makes no request. Missing fallback configuration does not block a valid primary; an invalid primary never silently becomes the fallback.

Each logical call freezes both configurations and credentials. Only timeout, network disconnect, HTTP 408/429 and 5xx can trigger one fallback attempt. Authentication, balance, input, cancellation, configuration, model identity and output validation errors stop the chain. Every attempt checks cancellation and business validity. Fast/deep total deadlines are 120/300 seconds including queueing, constrained by the caller's shorter budget. With a ready fallback, the primary gets at most 30/120 seconds and half the remaining time; fallback uses only the balance. Timeout resolves once without waiting for an uncooperative service, and late results are discarded. Only model calls repeat; candidates, original writes and supplement adoption remain owned by Notes.

Writing Help displays each role's readiness, independent service key controls and tests for the exact selected model. Tests have no fallback, use sample content and lose their result when the relevant chain or key changes. Deep tests use the streaming transport, as do both deep chain attempts; fast and embedding retain their existing transport. Embedding settings remain in Notes. Kimi Code always thinks; its declared token budget includes reasoning and output, while only content is returned. Notes supplements declare 8,192 ordinary tokens and 32,768 thinking tokens; classification declares 512/16,384. First-title generation declares 128/16,384 and keeps its shorter business deadlines. The capability and attempt boundaries are defined in [Model capabilities](../../openspec/specs/model-capabilities/spec.md).

## Safety boundaries

- Requests have a bounded encoded size.
- Calls within one frozen text invocation are serialized; independent flows use separate actors. Fast and foreground embedding do not wait behind a deep answer.
- A configured model must be confirmed by a valid returned model identifier; a mismatch discards the result.
- Cancellation propagates through queued and running work.
- Runtime logs record bounded stages, identifiers, outcomes, and timing without draft text or keys.

Provider transport details are in [AI provider implementation](ai-provider-implementation.md).

## Notes embeddings

Related History consumes the centrally configured embedding capability, currently backed by DashScope and `notesEmbedding` credential namespace. It does not change the chat-completion parser or the selected deep generation binding. The Embedding Service card is inside Apple Notes settings. It uses the same restricted file storage and masked input as other services, with no saved-key echo. Editing, replacing or removing the key invalidates tests and history preparations. Each explicit test validates a fixed non-private sample.

Embedding document/query requests use the same frozen provider/endpoint/model/dimension/processing profile. Batches contain at most 20 texts, each at most 16,384 UTF-8 bytes; encoded requests are capped at 350 KB and responses at 2 MB. The client maps by `text_index` and rejects wrong counts, duplicate/missing indices, nonfinite/zero vectors and wrong dimensions. Separate single-request foreground and indexing lanes prevent full indexing from occupying the query lane; queued callers are bounded. Requests default to five-minute request and resource timeouts per attempt, with at most two retries for selected network errors, 429 and 5xx. Authentication errors are explicit. Notes writes are never retried by this path.

Only current-scope snippets with application-owned source IDs enter the history prompt. Content filtering precedes the limit of ten distinct candidate notes; at most five source associations are displayed. Search History uses the same selection policy and scoped coverage snapshot. Each displayed historical association must reference a supplied ID and matching evidence. The Notes parser tolerates common format variations and ignores extra metadata; invalid or duplicate entries are skipped independently while valid insights and associations are retained. Unusable structured output is not rendered as raw JSON. See the Apple Notes action documentation for the accepted forms and bounds. Retrieval failures can omit history while ordinary suggestion generation continues. Related History off, missing key or a cleared/unstarted index leaves the ordinary Notes path available.

Notes generation explicitly logs its supplement purpose without selecting or activating a provider-level supplement prompt. A fixed diagnostic report distinguishes valid empty output, history-only output and parser rejection. The deadline selects one preparation result; final rendering/provenance handling reports separate adopted counts under the same action request identity. No diagnostic report contains draft or source text.

## Diagnostics

Logical call and attempt identities connect capability, primary/fallback role, requested/actual model, bounded failure class, elapsed time and final outcome. Runtime logs contain no text or keys. The opt-in `ModelDiagnostics` content receiver remains available, but Notes does not install one. No Personal Agent session is created or updated. Existing archives and historical metadata remain untouched.
