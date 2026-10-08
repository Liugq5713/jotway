# Product overview

> Role: **Current**

Jotway is a native macOS launcher for short, in-the-moment input. The user opens a small panel, types a sentence, checks or changes the proposed destination, and presses Enter. Jotway hands the content to the chosen action and leaves no local inbox behind.

## Main flow

1. Open the quick record panel from the global shortcut, menu bar, Dock, or application launch.
2. Enter plain text. Markdown-looking syntax, `/`, and `、` remain literal text; pasted rich text loses its styling, while image-only and file input is ignored.
3. Jotway combines explicit selection, local matching, Jev's suggestion, and the default action to choose a destination. A direct application name or `打开 应用名` can resolve to a local application launch without opening a separate command menu.
4. Press Enter or Command+Enter in the editor to execute. If the target is Set Up Notes, Enter opens configuration and retains the draft; after setup, press Enter again to save. Shift+Enter inserts a newline.
5. When a text submission is accepted, the panel clears and closes and the next draft uses automatic routing. Failure restores the submitted text and its routing mode unless the new draft has already been edited or its routing changed; otherwise the failed submission is retained separately.

## Quick record panel appearance

The panel follows the system light or dark appearance. Both use an opaque neutral surface and a 1 pt inner outline, so desktop colors do not affect the card and Reduce Transparency needs no translucent fallback. Increase Contrast strengthens the outline and uses semantic text colors.

| Element | Light | Dark |
|---|---|---|
| Card / outline | `#FAFBFC` / `#DCE0E5` | `#202226` / `#3F4248` |
| Body / secondary text and placeholder | `#24262A` / `#777C85` | `#E7E9EE` / `#959BA7` |
| Target button / label | `#EDF0F4` / `#5B6471` | `#2C2F35` / `#B9C1CD` |
| Return keycap / cursor and Return symbol | `#DFE5ED` / `#285BAF` | `#3A4350` / `#72BDED` |

The right-aligned target button uses 12 pt medium text, a 6 pt corner radius, and 7 pt horizontal / 3 pt vertical padding. It has no blue outline; the Return symbol and explicit-selection marker keep their blue accent. The Return hint and candidate-menu keyboard hints use centered system symbols in uniform 16 pt square keycaps. Action titles and status remain one line with truncation, full accessibility labels, and their existing tooltips. Reminder and Calendar plans use a separate result row above the target button: destination and absolute time on one line, or two lines in narrow layouts. Full destination and frozen time zone remain available through hover and VoiceOver. The editor gives up this row’s height before scrolling, keeping the action row visible. Candidate cards share the neutral surface without changing their layout or interaction.

The action name is the single target button, with a Return keycap hint for a nonempty draft and no separate dropdown arrow or execution button. Clicking it opens or closes the candidate menu, even for an empty draft or a single candidate. Empty drafts show Choose an App, or the explicitly selected target, without a Return hint. Selecting a target pins it to the draft through edits and panel reopening; selecting the current automatic target also establishes explicit mode. The menu's Let Jotway Choose action releases that choice immediately. Only accepted submission, a completed edit that clears the draft, or Let Jotway Choose ends the choice. An unavailable explicit target remains visible until the user changes mode or target.

Tab focuses the target button; Return or Space opens its menu. Enter inside the menu selects a target or changes mode and restores editor focus without submitting; Escape closes only the menu. Option+Up/Down cycles targets separately and never cycles through Let Jotway Choose. Text composition takes precedence over these keys.

The candidate menu and window height update without layout animation, so opening or closing the menu does not animate the editor's position.

The area outside each card's rounded border stays transparent, without an outer shadow or gray backdrop.

The default panel width is 560 pt and can narrow to 360 pt. The input card has a 14 pt corner radius and starts at 96 pt: 20 pt top padding, a 26 pt minimum editor, 12 pt gap, a 22 pt action row, and 16 pt bottom padding. The action row keeps its space when the draft is empty. Actual left/right text padding is 20 pt, including native text-container insets and line-fragment padding, and aligns with the status text. Initial window sizing uses the same dimensions. The card grows automatically downward from its top edge to 360 pt; the editor scrolls internally after reaching 290 pt without a plan result row, keeping the action row visible.

Dragging a window edge resizes the usable editor area along with the input card. A manually chosen height takes precedence over automatic growth until the panel is opened again, and may exceed the automatic height limit. The action row and any plan result keep their space; longer text scrolls inside the remaining editor area. The candidate menu adds height below the input card. When the window reaches its size or screen limit, the manual input height shrinks to keep those controls visible.

Body and placeholder use the regular 16 pt system font. Ordinary Chinese and English baselines are 26 pt apart: extra line spacing preserves the native font-height cursor and selection instead of stretching them to the full spacing. Taller glyphs may expand their line rather than being clipped. Both use the same native TextKit layout geometry as the cursor and selection. The placeholder disappears immediately when text or marked text appears, canceling any earlier fade. Deleting all text allows a short fade-in; Reduce Motion shows it immediately. Text uses the full editor width without a persistent Escape badge. Escape still closes the panel while retaining the draft.

Clicking unused space inside the input card returns keyboard focus to the editor while preserving its text and selection. Dragging that background moves the panel; text selection and action buttons keep their own mouse behavior.

## Bundled actions

- Apple Notes: preserves the complete original text and can append separate AI thinking assistance; the factory default action.
- Apple Reminders: creates a reminder for task-like input.
- Apple Calendar: creates an event for time-bound input.
- Chrome: opens a Google search.
- ChatGPT: opens a new desktop conversation with the draft prefilled for manual send.

Apple Notes is the preferred default. When it cannot execute, Jotway tries another ready storage action. If none is ready, Set Up Notes is the fallback. Unconfigured Notes remains available for explicit selection and local Notes prefixes even when another storage action supplies the fallback. Chrome and ChatGPT never become implicit fallbacks. An unavailable recognition suggestion is ignored so it cannot remove the fallback; an unavailable explicit selection still reports its error rather than silently choosing another action.

Notes setup preserves the draft and selection, pauses recognition, and uses a single configuration window. It is not a submission: completing or cancelling setup returns to the original draft without execution feedback or automatic saving. Successful setup selects Notes; the user confirms again to save. The explicitly requested connection test creates a disclosed test note, never the draft. Permission refusal retains the saved location and offers Automation settings guidance and another folder read.

## Product boundaries

- The editable draft disappears when the process exits. When local operation capture is enabled, stable unsubmitted text is also persisted for manual review; it is never restored as a draft.
- Jotway does not provide an inbox, browsable content history, cards, completion state, or Summary.
- The editor accepts only multi-line plain text. It does not render or structurally edit Markdown, and it does not accept images, files, or rich-text attachments.
- Local operation records include full input versions, routing, choices, and execution observations. Capture, retention (default 90 days), manual JSONL/CSV export, and deletion are controlled in App Suggestions settings. Records do not automatically change rules.
- Intent recognition proposes a destination; it never performs an action without the user's Enter confirmation.
- Action failure restores the input rather than silently dropping it.

## Design principles

- One sentence in, one explicit outcome out.
- A usable execution or configuration path exists even when recognition is unavailable.
- Local and explicit signals outrank a model guess.
- Each action owns one descriptor, availability, preparation, and execution.
- Optional AI processing must degrade to a usable non-AI path.
