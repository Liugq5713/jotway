# Apple Notes action

> Role: **Current**

Apple Notes is a storage action and the factory default fallback. It is available after the user selects an account/folder destination in Settings → Actions.

## Routing

Explicit phrases such as “记一下” or “存备忘录” can match locally. Jev may also suggest Notes for content the user wants to keep. When no stronger route exists, the configured default action receives the draft.

## Execution

1. Reuse the prepared action when available, otherwise run the action text processor once.
2. Convert plain text to Notes HTML.
3. Create the note through the Apple Notes adapter.

The title comes from the first meaningful line. The editor and action payload contain plain text only: Markdown-looking text is passed through literally, and Jotway has no image, file, rich-text, or attachment payload.

## Success and failure

Success requires a confirmed note identifier.

Missing destination, empty content, permission failure, or an unconfirmed response returns an error to the panel. The panel restores the original text unless a new draft already exists, in which case it retains the failed submission separately.

## Boundaries

- Jotway does not keep a copy of the created note.
- Apple Notes may be the default action; Chrome may not.
