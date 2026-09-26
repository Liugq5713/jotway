# Jev intent recognition

> Role: **Current**

Jev proposes an action for the current draft. It is an advisory routing layer: no network response executes an action by itself.

## Routing priority

At confirmation time Jotway uses:

1. the user's explicit target selection;
2. a saved user phrase rule;
3. a local action keyword match;
4. a current, available Jev suggestion;
5. the ready default action, or Notes setup when no storage action is ready.

This order prevents a model guess from overriding a direct phrase such as “提醒我” or a deliberate user correction.

Missing keys, pending requests, timeouts, and unavailable model targets cannot remove the fallback. Ready storage actions are preferred; when none is available, [Set Up Notes](apple-notes.md) opens configuration while retaining the draft. This local setup route does not require a model result.

## Request boundary

The model request starts only when a saved Jev key is available and the draft is within the size limit. Jotway sends the current text plus criteria only for available actions that explicitly declare a capture binding. A model capture result must name one of that request's options; a Google result must match the request snapshot's available web-search binding. Actions whose binding is `.none` and actions that need setup do not enter the external protocol. Setup candidates are separate from ready execution snapshots and are never prewarmed. The rule version is defined in source (`Jev.ruleVersion`, currently `jev-intent-v8`) and is attached to diagnostics.

Application launch is matched locally and is not delegated to the model. Recognition snapshots include both the Jev configuration revision and action-registry revision, so a result from an older action configuration is discarded.

## Suggestion and selection

The proposed destination appears before execution. Candidate construction and explicit selection belong to `LauncherSession`, not the recognition request. The user can cycle through executable targets and module-provided setup entries with the option-arrow controls or choose a visible candidate. Unconfigured Notes remains selectable and supports the existing local Notes prefixes. Changing the target is local and does not send another recognition request.

Manual selection remains available while recognition is pending, when the key is missing, after recognition fails, and when the draft is too large for the model. A single non-default candidate can be selected explicitly instead of becoming an implicit fallback. A delayed suggestion never overwrites an explicit stable ID. If that selected target later becomes disabled or unavailable, Jotway preserves the choice and reports that it cannot currently execute.

Enter confirms the final target. For Set Up Notes it opens configuration and pauses recognition while preserving the draft and selection. Completing or cancelling setup returns to the original draft; completion selects Notes and requires another Enter to save. Setup has separate start/finish observations and creates no execution attempt. Shift+Enter remains newline input. Rules, keywords, a current suggestion, and fallback use the same source-bearing route decision shown by the UI.

## Local operation records

One local record captures stable input, recognition requests and results, the final route actually shown, genuine user choices, confirmations, and external effects. Manual, rule, keyword, default, and no-key routes are included alongside model suggestions. A background result cannot replace the presentation that preceded the user's first choice; setup completion is not a user choice. Records never feed back into routing automatically.

The English-only interface does not constrain input language. Local action matching continues to accept the existing Chinese phrases and also accepts explicit English prefixes: `save to notes` / `take a note`, `remind me` / `add a reminder`, `add to calendar` / `schedule a meeting`, and `search google` / `google search`. English matching is case-insensitive and requires an end, whitespace, or punctuation boundary after the prefix. Jev and AI rewriting likewise preserve the draft's language by default; UI resources do not participate in routing or model protocols.

Records include full unsubmitted text when enabled. Intent Recognition settings provides capture control, retention (90 days by default), completeness and storage status, JSONL/CSV export, and clear. There is no independent corrections/adoption store or settings list. Local Rules remain manually editable and are not deleted with records. See [Data model](../development/data-model.md).

## Diagnostics and privacy

Runtime diagnostics keep request IDs, rule/model identifiers, bounded scores/reasons, routing source, and timing. They exclude draft text, keys, and full provider responses. Exported logs include the active rule definition for later interpretation.

External API details and remaining uncertainty are kept in [Jev API reference](jev-api-research.md).
