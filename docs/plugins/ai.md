# AI capability

> Role: **Current**

Jotway has two AI-related paths with different responsibilities:

1. Jev suggests the destination action. It is documented separately.
2. A storage action may request optional content assistance before writing. Reminder and Calendar time interpretation is local and separate.

## Action text processing

Storage actions use DeepSeek independently of the general provider selected in AI settings:

- Notes uses a dedicated supplement processor. The exact original draft remains owned by the application; the model returns a bounded structured result containing zero to three short background points, exploratory ideas, or clarifying questions, plus optional tags. The application appends valid content under “AI 补充” and constructs the final HTML itself.
- Reminders uses `AITextProcessor` to clean reminder wording.
- Calendar uses `AITextProcessor` to clean event wording.

Each action keeps its independent enable preference. Notes reuses its existing on/off value but stores supplement preferences separately from legacy rewrite styles, which remain stored and inactive. The default remains enabled when no value exists. Notes preserves original text, title source, blank lines, spacing, tabs, indentation and literal text syntax regardless of model output. Fixed tags and enabled AI tags are deduplicated only in the appended area; AI tags share the supplement request and are disabled when supplements are off.

Reminder and Calendar body-style settings and fallback behavior remain unchanged. Their schedules always come from the original draft through the local deterministic resolver; model output and style instructions cannot change those frozen times.

Missing key, network error, timeout, empty response, or invalid output produces no Notes supplement or AI tags; original text and configured fixed tags are still saved. It does not return a fallback copy of the original to append. For Reminders and Calendar, these failures retain their original-body fallback and never turn a blocked time into a writable request. Cancellation propagates through both paths and prevents the cancelled write.

Notes uses one prepared result and one create request per accepted confirmation. It does not create a note first and edit it later. Prewarming uses existing action/configuration identities and is invalidated by changes. Custom supplement preferences cannot authorize replacing the original, inventing user background, or implying that external information was searched or verified. Draft instructions are treated as recorded content.

## General provider configuration

All builds register DeepSeek and Moonshot through the shared provider installation. Settings save the source/model choice, key, manual Instructions, and prompt configuration; a connection test uses fixed sample content.

Configuration is frozen before a logical request enters the queue. Changing settings affects new requests, not one already queued or running.

## Safety boundaries

- Requests have a bounded encoded size.
- Provider calls are serialized by the shared actor.
- A configured model must be confirmed by a valid returned model identifier; a mismatch discards the result.
- Cancellation propagates through queued and running work.
- Runtime logs record bounded stages, identifiers, outcomes, and timing without draft text or keys.

Provider transport details are in [AI provider implementation](ai-provider-implementation.md).
