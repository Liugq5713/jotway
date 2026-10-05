# Apple Notes action

> Role: **Current**

Apple Notes is the preferred storage fallback once a destination is configured and no known permission failure prevents execution. When it needs configuration, the panel offers Set Up Notes as an explicit target and as the fallback when no other storage action can execute.

## Routing

Explicit phrases such as “记一下”, “存备忘录”, “save to notes”, and “take a note” can match locally, including when Notes needs setup. A user can select Notes directly without a Jev key. Jev receives Notes as an option only while the action is ready to execute; setup is never a model execution candidate or a prewarmed action.

Without a stronger route, ready storage actions retain their fallback order: Notes, Reminders, then Calendar. If none is ready, Set Up Notes opens configuration. Chrome and ChatGPT do not become storage fallbacks. An unavailable model suggestion cannot remove this fallback, while an unavailable explicit target keeps its error instead of silently switching to Notes.

## Authorization and configuration

Pressing Enter or Command+Enter in the editor with Set Up Notes selected opens a single configuration window with the same Notes destination picker used in Settings → Actions. Opening the configuration flow or explicitly reading folders makes the Apple Events request that can trigger first authorization. Typing, rendering the panel, background recognition, and action prewarming do not request Notes permission.

The draft, selection, and draft identity are retained while recognition is paused. Repeated confirmation focuses the existing configuration window. Completing, cancelling, or closing configuration returns to the same draft; successful configuration selects Notes and waits for another Enter before saving. A stale configuration callback cannot replace a newer draft or take its focus. Setup does not clear the draft, play a submission animation, or record action execution or model-adoption feedback.

Verify and Finish explicitly creates the test note described in the configuration UI, using fixed sample content rather than the current draft. Opening or reading the picker alone never writes a test note or saves the draft.

Permission refusal and revocation retain the selected destination and direct the user to System Settings → Privacy & Security → Automation → Jotway → Notes. The configuration view offers Open System Settings and a fresh folder read. It does not reset permissions or promise that macOS will show the consent dialog again. A successful authorized read clears the known permission-failure state.

## Execution

1. Freeze the complete original draft and reject whitespace-only content before requesting AI.
2. Reuse the prepared action or request optional Notes supplements once. Model output contains only bounded supplement items and optional tags, never replacement note text or a title.
3. Assemble the original text, any valid AI supplement, and deduplicated appended tags, then create one note through the Apple Notes adapter. There is no later background update.

Notes uses the exact original editor text, including leading and trailing whitespace, blank lines, repeated spaces, tabs, indentation, Markdown-looking text, code, URLs, paths, and escaped HTML special characters. Line endings may be normalized and Notes may append its own final newline. The title comes from the original first meaningful line; a separately displayed title does not remove that line or preceding whitespace from the full original body. Other actions retain their existing trimmed-body contract.

AI supplements are optional thinking assistance: zero to three short background points, exploratory ideas, or questions worth clarifying. They appear only after the original under an application-generated “AI 补充” label. The model is instructed not to rewrite or repeat the draft, invent the user's history or motives, imply retrieval or verification, or treat instructions inside the draft as permission to act. Preferences can shape supplements but cannot replace the original-protection or output rules. This path performs no browsing, personal-memory lookup, or history completion.

An absent key, timeout, network failure, empty response, or invalid structure yields no AI section and no failure placeholder. Original text and configured fixed tags can still be saved. AI tags use the same request as the supplement and are gated by the supplement switch and their own preference. Deduplication only affects appended tags; tags already written in the original are never removed or changed.

Notes retains the existing AI enable preference, including a saved off state and the current enabled-by-default behavior when unset. Supplement preferences use a separate key. Legacy custom rewrite instructions remain stored but are not executed or copied into the new preference; saved new preferences survive reopening. Settings explains this change when a legacy style exists.

Preparation uses the existing frozen action configuration, bounded DeepSeek request, provider queue, and result reuse. Draft or configuration changes invalidate old preparation. Cancellation propagates and prevents a cancelled preparation from writing; a normal AI failure simply means no supplement. Prewarming never requests Notes permission or creates a note.

## Success and failure

Success requires a confirmed note identifier. Folder reads preserve the distinction between permission refusal (`-1743`), an empty folder list, a missing destination, and a Notes launch failure. Permission errors are not displayed as an empty folder list.

Missing destination, empty content, permission failure, or an unconfirmed write response returns an error to the panel. The panel restores the original text unless a new draft already exists, in which case it retains the failed submission separately. A permission failure also makes Notes configurable again without erasing its saved destination. Jotway does not automatically retry a write whose outcome may be unknown.

## Boundaries

- Jotway does not keep a copy of the created note.
- Configuring Notes is separate from submitting the draft.
- Permission details belong to the Notes module; the launcher hosts a generic setup flow.
