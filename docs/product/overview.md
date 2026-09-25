# Product overview

> Role: **Current**

Jotway is a native macOS launcher for short, in-the-moment input. The user opens a small panel, types a sentence, checks or changes the proposed destination, and presses Enter. Jotway hands the content to the chosen action and leaves no local inbox behind.

## Main flow

1. Open the quick record panel from the global shortcut, menu bar, Dock, or application launch.
2. Enter plain text. Markdown-looking syntax, `/`, and `、` remain literal text; pasted rich text loses its styling, while image-only and file input is ignored.
3. Jotway combines explicit selection, local matching, Jev's suggestion, and the default action to choose a destination. A direct application name or `打开 应用名` can resolve to a local application launch without opening a separate command menu.
4. Press Enter to execute. Shift+Enter inserts a newline.
5. On success the panel clears and closes. On failure the draft is restored with an actionable message.

## Quick record panel appearance

The panel follows the system light or dark appearance. Dark appearance uses a graphite surface; light appearance uses a cool, pale surface. Both have a restrained blue edge, blue action controls, and monospaced key hints. A nearly opaque color layer over native material keeps text legible across desktop backgrounds. Reduce Transparency uses the same colors with a fully opaque surface; Increase Contrast strengthens the outline while semantic text colors preserve the hierarchy from body text to placeholder and chrome.

The area outside each card's rounded border stays transparent, without an outer shadow or gray backdrop.

The default panel width is 560 pt and can narrow to 360 pt. The input card has a 14 pt corner radius and keeps a minimum height of 88 pt with 16 pt horizontal and 14 pt vertical padding. Editor text remains 15 pt, with a small amount of extra spacing between lines for multi-line drafts. Text uses the full editor width without a persistent Escape badge. The action row keeps its existing placement, and Escape still closes the panel while retaining the draft.

## Bundled actions

- Apple Notes: saves text; the factory default action.
- Apple Reminders: creates a reminder for task-like input.
- Apple Calendar: creates an event for time-bound input.
- Chrome: opens a Google search.

Apple Notes is the preferred default. When it is not configured, Jotway tries another available storage action. Chrome never becomes an implicit fallback.

## Product boundaries

- Unconfirmed draft text is memory-only and disappears when the process exits.
- Jotway does not provide an inbox, record history, cards, completion state, Summary, or export archive.
- The editor accepts only multi-line plain text. It does not render or structurally edit Markdown, and it does not accept images, files, or rich-text attachments.
- Confirmed routing may persist the full draft text locally as intent feedback. Corrections are capped at 200; accepted samples currently have no retention limit or user-facing clear control.
- Intent recognition proposes a destination; it never performs an action without the user's Enter confirmation.
- Action failure restores the input rather than silently dropping it.

## Design principles

- One sentence in, one explicit outcome out.
- A safe default exists even when recognition is unavailable.
- Local and explicit signals outrank a model guess.
- Each action owns one descriptor, availability, preparation, and execution.
- Optional AI processing must degrade to a usable non-AI path.
