# Apple Notes action

> Role: **Current**

Apple Notes is the preferred storage fallback once a destination is configured and no known permission failure prevents execution. When it needs configuration, the panel offers Set Up Notes as an explicit target and as the fallback when no other storage action can execute.

## Routing

Explicit phrases such as “记一下”, “存备忘录”, “save to notes”, and “take a note” can match locally, including when Notes needs setup. A user can select Notes directly without a Jev key. Jev receives Notes as an option only while the action is ready to execute; setup is never a model execution candidate or a prewarmed action.

Without a stronger route, ready storage actions retain their fallback order: Notes, Reminders, then Calendar. If none is ready, Set Up Notes opens configuration. Chrome and ChatGPT do not become storage fallbacks. An unavailable model suggestion cannot remove this fallback, while an unavailable explicit target keeps its error instead of silently switching to Notes.

## Authorization and configuration

Pressing Enter or Command+Enter in the editor with Set Up Notes selected opens a single configuration window with an Allow Access button and an explanation of the default destination. Clicking Allow Access makes the Apple Events request that can trigger the macOS consent dialog. Opening the setup window or action settings page, typing, rendering the panel, background recognition, and action prewarming do not request Notes permission.

After authorization, Jotway keeps the saved destination when it is still available. Otherwise, it selects the default folder in the default Notes account, then another account's default folder, then the first exposed folder if no account default is available. Successful launcher setup completes automatically. Settings → Apps shows the selected destination and offers Change… to open the optional folder picker; the launcher setup window has no picker. Authorization and destination selection do not create a test note, and no verification step is required.

The draft, selection, and draft identity are retained while recognition is paused. Repeated confirmation focuses the existing configuration window. Completing, cancelling, or closing configuration returns to the same draft; successful configuration selects Notes and waits for another Enter before saving. A stale configuration callback cannot replace a newer draft or take its focus. Setup does not clear the draft, play a submission animation, or record action execution or model-adoption feedback.

Permission refusal and revocation retain the selected destination and direct the user to System Settings → Privacy & Security → Automation → Jotway → Notes. When authorization or the saved destination needs repair, settings and launcher setup offer Open System Settings and Allow Access Again. They do not reset permissions or promise that macOS will show the consent dialog again. A successful authorized read clears the known permission-failure state.

## Execution

1. Freeze the complete original draft and reject whitespace-only content before requesting AI.
2. Reuse the prepared action or request optional Notes supplements once. Model output contains only bounded supplement items and optional tags, never replacement note text or a title.
3. Assemble the original text, any valid AI supplement, and deduplicated appended tags, then create one note through the Apple Notes adapter. There is no later background update.

Jotway includes the complete original draft once in each generated HTML and plain-text representation, without prepending a derived title or removing the first line. It preserves leading and trailing whitespace, blank lines, repeated spaces, tabs, indentation, intentional repeated lines, Markdown-looking text, code, URLs, paths, and escaped HTML special characters. Line endings may be normalized and a final newline may be appended. Apple Notes determines the displayed title and presentation. Other actions retain their existing trimmed-body contract.

AI supplements are optional thinking assistance: zero to three short background points, exploratory ideas, or questions worth clarifying. They appear only after the original under an application-generated “AI 补充” label and separator, in a dedicated monospaced `<pre>` block that wraps long lines. The original and appended tags keep their normal body font so the generated additions are visually distinct. The model is instructed not to rewrite or repeat the draft, invent the user's history or motives, imply retrieval or verification, or treat instructions inside the draft as permission to act. Preferences can shape supplements but cannot replace the original-protection or output rules. This path performs no browsing, personal-memory lookup, or history completion.

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
