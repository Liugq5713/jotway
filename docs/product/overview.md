# Product overview

> Role: **Current**

Jotway is a native macOS launcher for short, in-the-moment input. The user opens a small panel, types a sentence, checks or changes the proposed destination, and presses Enter. Jotway hands the content to the chosen action and leaves no local inbox behind.

## Main flow

1. Open the quick record panel from the global shortcut, menu bar, Dock, or application launch.
2. Enter plain text. Markdown-looking syntax, `/`, and `、` remain literal text; pasted rich text loses its styling, while image-only and file input is ignored.
3. Jotway combines explicit selection, local matching, Jev's suggestion, and the default action to choose a destination. A direct application name or `打开 应用名` can resolve to a local application launch without opening a separate command menu.
4. Press Enter to execute. If the target is Set Up Notes, Enter opens configuration and retains the draft; after setup, press Enter again to save. Shift+Enter inserts a newline.
5. On success the panel clears and closes. On failure the draft is restored with an actionable message.

## Quick record panel appearance

The panel follows the system light or dark appearance. Both use an opaque neutral surface and a 1 pt inner outline, so desktop colors do not affect the card and Reduce Transparency needs no translucent fallback. Increase Contrast strengthens the outline and uses semantic text colors.

| Element | Light | Dark |
|---|---|---|
| Card / outline | `#FAFBFC` / `#DCE0E5` | `#202226` / `#3F4248` |
| Body / secondary text and placeholder | `#24262A` / `#777C85` | `#E7E9EE` / `#959BA7` |
| Action button / label | `#EDF0F4` / `#5B6471` | `#2C2F35` / `#B9C1CD` |
| Return keycap / cursor and Return symbol | `#DFE5ED` / `#285BAF` | `#3A4350` / `#72BDED` |

The right-aligned action button uses 12 pt medium text, a 6 pt corner radius, and 7 pt horizontal / 3 pt vertical padding. It has no blue outline; the Return symbol and explicit-selection marker keep their blue accent. Action titles and status remain one line with truncation, full accessibility labels, and their existing tooltips. Candidate cards share the neutral surface without changing their layout or interaction.

The area outside each card's rounded border stays transparent, without an outer shadow or gray backdrop.

The default panel width is 560 pt and can narrow to 360 pt. The input card has a 14 pt corner radius and starts at 90 pt: 18 pt top padding, a 26 pt minimum editor, 10 pt gap, a 22 pt action row, and 14 pt bottom padding. The action row keeps its space when the draft is empty. Actual left/right text padding is 20 pt, including native text-container insets and line-fragment padding, and aligns with the status text. Initial window sizing uses the same dimensions. The card grows downward from its top edge to 360 pt; the editor scrolls internally after reaching 296 pt, keeping the action row visible.

Body and placeholder use the regular 16 pt system font. Ordinary Chinese and English baselines are 26 pt apart: extra line spacing preserves the native font-height cursor and selection instead of stretching them to the full spacing. Taller glyphs may expand their line rather than being clipped. Both use the same native TextKit layout geometry as the cursor and selection. The placeholder disappears immediately when text or marked text appears, canceling any earlier fade. Deleting all text allows a short fade-in; Reduce Motion shows it immediately. Text uses the full editor width without a persistent Escape badge. Escape still closes the panel while retaining the draft.

Clicking unused space inside the input card returns keyboard focus to the editor while preserving its text and selection. Dragging that background moves the panel; text selection and action buttons keep their own mouse behavior.

## Bundled actions

- Apple Notes: saves text; the factory default action.
- Apple Reminders: creates a reminder for task-like input.
- Apple Calendar: creates an event for time-bound input.
- Chrome: opens a Google search.
- ChatGPT: opens a new desktop conversation with the draft prefilled for manual send.

Apple Notes is the preferred default. When it cannot execute, Jotway tries another ready storage action. If none is ready, Set Up Notes is the fallback. Unconfigured Notes remains available for explicit selection and local Notes prefixes even when another storage action supplies the fallback. Chrome and ChatGPT never become implicit fallbacks. An unavailable recognition suggestion is ignored so it cannot remove the fallback; an unavailable explicit selection still reports its error rather than silently choosing another action.

Notes setup preserves the draft and selection, pauses recognition, and uses a single configuration window. It is not a submission: completing or cancelling setup returns to the original draft without execution feedback or automatic saving. Successful setup selects Notes; the user confirms again to save. The explicitly requested connection test creates a disclosed test note, never the draft. Permission refusal retains the saved location and offers Automation settings guidance and another folder read.

## Product boundaries

- Unconfirmed draft text is memory-only and disappears when the process exits.
- Jotway does not provide an inbox, record history, cards, completion state, Summary, or export archive.
- The editor accepts only multi-line plain text. It does not render or structurally edit Markdown, and it does not accept images, files, or rich-text attachments.
- Confirmed routing may persist the full draft text locally as intent feedback. Corrections are capped at 200; accepted samples currently have no retention limit or user-facing clear control.
- Intent recognition proposes a destination; it never performs an action without the user's Enter confirmation.
- Action failure restores the input rather than silently dropping it.

## Design principles

- One sentence in, one explicit outcome out.
- A usable execution or configuration path exists even when recognition is unavailable.
- Local and explicit signals outrank a model guess.
- Each action owns one descriptor, availability, preparation, and execution.
- Optional AI processing must degrade to a usable non-AI path.
