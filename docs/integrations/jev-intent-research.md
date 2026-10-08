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

The model request starts only when a saved Jev key is available and the draft is within the size limit. Jotway sends the current text and fixed request, operation, and task-scope questions, plus capture criteria only for available actions that explicitly declare a capture binding. A model capture result must name one of that request's options. Google and conversation results must match the request snapshot's available `.webSearch` and `.conversation` bindings respectively; an unavailable target is discarded. Actions whose binding is `.none` and actions that need setup do not enter the external protocol. Setup candidates are separate from ready execution snapshots and are never prewarmed. The rule version is defined in source (`Jev.ruleVersion`, currently `jev-intent-v9`) and is attached to diagnostics.

After the current-request and outer-operation confidence checks, task scope distinguishes conversation from web lookup and storage. Direct explanations, how-to answers, analysis, summaries, translations, writing, and generated content can suggest ChatGPT. Explicit Google/Chrome search takes precedence; webpages, links, sources, existing templates, and current public-fact lookups remain web searches. Notes, reminders, and actual calendar scheduling remain capture routes. A quoted, negated, deferred, unsupported, or multiple-destination request cannot become a conversation merely because it contains assistant-task wording. Conversation uses the same validated choice-confidence and probability thresholds as other task-scope results.

Application launch is matched locally and is not delegated to the model. Recognition snapshots include both the Jev configuration revision and action-registry revision, so a result from an older action configuration is discarded.

## Suggestion and selection

The proposed destination appears before execution. `LauncherSession` owns candidates and each draft’s automatic or explicit routing mode. Explicit selection is bound to the draft ID, including when the user selects the current automatic suggestion. It survives text edits, a nonempty replacement, adding a clipboard quote, focus loss, dismissal, and reopening. Recognition and action preparation still use the latest text and configuration; a retained target never licenses an older body or time plan.

One target button shows the current action name and a Return keycap hint when there is text; an empty draft shows Choose an App or its explicit choice without the hint. Clicking the button opens or closes the candidate menu; Enter or Command+Enter in the editor confirms execution. Registered executable actions and setup entries are available without a recognition snapshot, including a single candidate. Local application candidates still require matching current text. An empty draft can retain a choice but cannot prepare a write or create an execution attempt. Enter in the editor may dismiss it without clearing that choice.

The candidate menu offers Let Jotway Choose as a separate mode operation. It closes the menu, keeps text and selection, removes the explicit marker, and immediately applies the current rules, keywords, valid suggestion, or fallback. It does not wait for a model response and is not part of Option+Up/Down target cycling. In automatic mode the menu displays that state without offering a repeated reset. Mouse and keyboard can operate the target button and automatic-mode control. Tab focuses the button, Return or Space opens the menu, menu Enter selects or changes mode and restores editor focus, and menu Esc closes. These menu operations do not submit the draft, and Chinese input composition takes precedence.

Manual selection remains available while recognition is pending, without a key, after recognition fails, and for drafts too large for the model. Late suggestions cannot replace an explicit stable ID. If the selected action becomes disabled, unconfigured, removed, or otherwise unavailable, its name or an unavailable message remains visible. Confirmation reports the problem; the user can choose another target or Let Jotway Choose instead of being silently redirected.

A completed edit that changes meaningful content to whitespace-only ends the choice. Composition intermediates and an atomic nonempty replacement do not. Undoing a completed clear restores text without reviving the prior selection. A genuinely accepted submission also ends the choice; its frozen request continues independently and the next draft starts automatically. Blocked confirmation or a rejected editor clear retains both text and mode.

On execution failure, the submitted text and its original mode return together only if the new draft has had neither edits nor routing operations. A new empty draft that has selected a target or returned to automatic is protected too. Otherwise `FailedSubmission` retains the old text and mode for explicit recovery. Restoring into an untouched empty draft restores the old mode; merging into an edited draft or one with routing activity retains the current mode, including automatic.

For Set Up Notes, confirmation opens configuration and pauses recognition while preserving text and routing mode. Cancellation retains that mode; successful setup explicitly selects Notes for the same original draft and requires another Enter to save. Setup is not a submission. For local application opening, actual dispatch acceptance releases the explicit choice even when existing rules retain the text. No dispatch retains the choice; a failed open restores the prior mode only while no newer text or routing operation has intervened.

Draft routing mode lives only in memory and is cleared on application exit, crash, or restart. It does not change global fallback preferences or the automatic priority order. Shift+Enter remains newline input.

## Local operation records

One local record captures stable input, recognition requests and results, the final route actually shown, genuine user choices, confirmations, and external effects. Manual, rule, keyword, default, and no-key routes are included alongside model suggestions. A background result cannot replace the presentation that preceded the user's first choice; setup completion is not a user choice. Records never feed back into routing automatically. An actual empty-draft selection can be recorded. Continuing that selection after an edit or reopening is distinguished from a new choice without fabricating another click or carrying an invalid input-version reference. Let Jotway Choose is a recorded mode change. Recording being disabled, cleared, or expired does not alter the live draft’s mode or recreate deleted choice records.

The English-only interface does not constrain input language. Local action matching continues to accept the existing Chinese phrases and also accepts explicit English prefixes: `save to notes` / `take a note`, `remind me` / `add a reminder`, `add to calendar` / `schedule a meeting`, and `search google` / `google search`. English matching is case-insensitive and requires an end, whitespace, or punctuation boundary after the prefix. Jev and AI rewriting likewise preserve the draft's language by default; UI resources do not participate in routing or model protocols.

Records include full unsubmitted text when enabled. App Suggestions settings provides capture control, retention (90 days by default), completeness and storage status, JSONL/CSV export, and clear. There is no independent corrections/adoption store or settings list. Your Phrases remain manually editable and are not deleted with records. See [Data model](../development/data-model.md).

## Diagnostics and privacy

Runtime diagnostics keep request IDs, rule/model identifiers, bounded scores/reasons, routing source, and timing. They exclude draft text, keys, and full provider responses. Exported logs include the active rule definition for later interpretation.

External API details and remaining uncertainty are kept in [Jev API reference](jev-api-research.md).

## Input and confirmation stability

Target labels continue to reflect the current valid route immediately, including fallback while an obsolete model suggestion is discarded. A fixed label slot and reserved Return/explicit-marker slots prevent that name change from moving the controls. A time result reserves space after its first appearance; editing and composition clear the old plan and its presentation receipt while retaining that space until the draft or panel presentation resets.

Input and recognition updates consume cached module availability. External probes run on separate presentation/configuration/workspace triggers. Confirmation captures the rendered destination before its live availability check and blocks if that check changes the target or changes an action into a setup route. The same Enter cannot silently execute the fallback. Existing routing priority, 500 ms recognition debounce, and 600 ms delayed recognition hint remain unchanged.
