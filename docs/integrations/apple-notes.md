# Apple Notes action

> Role: **Current**

Apple Notes is the preferred storage fallback once a destination is configured and no known permission failure prevents execution. When it needs configuration, the panel offers Set Up Notes as an explicit target and as the fallback when no other storage action can execute.

## Routing

Explicit phrases such as “记一下”, “存备忘录”, “save to notes”, and “take a note” can match locally, including when Notes needs setup. A user can select Notes directly without a Jev key. Jev receives Notes as an option only while the action is ready to execute; setup is never a model execution candidate or a prewarmed action.

Without a stronger route, ready storage actions retain their fallback order: Notes, Reminders, then Calendar. If none is ready, Set Up Notes opens configuration. Chrome and ChatGPT do not become storage fallbacks. An unavailable model suggestion cannot remove this fallback, while an unavailable explicit target keeps its error instead of silently switching to Notes.

## Authorization and configuration

Pressing Enter or clicking Set Up Notes opens a single configuration window with the same Notes destination picker used in Settings → Actions. Opening the configuration flow or explicitly reading folders makes the Apple Events request that can trigger first authorization. Typing, rendering the panel, background recognition, and action prewarming do not request Notes permission.

The draft, selection, and draft identity are retained while recognition is paused. Repeated confirmation focuses the existing configuration window. Completing, cancelling, or closing configuration returns to the same draft; successful configuration selects Notes and waits for another Enter before saving. A stale configuration callback cannot replace a newer draft or take its focus. Setup does not clear the draft, play a submission animation, or record action execution or model-adoption feedback.

Verify and Finish explicitly creates the test note described in the configuration UI, using fixed sample content rather than the current draft. Opening or reading the picker alone never writes a test note or saves the draft.

Permission refusal and revocation retain the selected destination and direct the user to System Settings → Privacy & Security → Automation → Jotway → Notes. The configuration view offers Open System Settings and a fresh folder read. It does not reset permissions or promise that macOS will show the consent dialog again. A successful authorized read clears the known permission-failure state.

## Execution

1. Reuse the prepared action when available, otherwise run the action text processor once.
2. Convert plain text to Notes HTML.
3. Create the note through the Apple Notes adapter.

The title comes from the first meaningful line. The editor and action payload contain plain text only: Markdown-looking text is passed through literally, and Jotway has no image, file, rich-text, or attachment payload.

## Success and failure

Success requires a confirmed note identifier. Folder reads preserve the distinction between permission refusal (`-1743`), an empty folder list, a missing destination, and a Notes launch failure. Permission errors are not displayed as an empty folder list.

Missing destination, empty content, permission failure, or an unconfirmed write response returns an error to the panel. The panel restores the original text unless a new draft already exists, in which case it retains the failed submission separately. A permission failure also makes Notes configurable again without erasing its saved destination. Jotway does not automatically retry a write whose outcome may be unknown.

## Boundaries

- Jotway does not keep a copy of the created note.
- Configuring Notes is separate from submitting the draft.
- Permission details belong to the Notes module; the launcher hosts a generic setup flow.
