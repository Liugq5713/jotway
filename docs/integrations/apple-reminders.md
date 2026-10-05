# Apple Reminders action

> Role: **Current**

Apple Reminders handles task-like input. It becomes available after authorization and destination setup in Settings → Actions.

## Authorization and destination

Clicking Authorize requests macOS access to Reminders. Opening the action settings page, typing, and action prewarming do not request permission. After authorization, Jotway keeps an available writable saved list; otherwise, it selects the system default reminder list, falling back to the first writable list if needed. Change… lets the user optionally choose another list. No test reminder or verification step is required.

Denied or revoked authorization preserves the saved list. When authorization or the destination needs repair, the page offers a link to System Settings plus Authorize Again. Successful authorization restores availability when a writable destination exists. Reminders has no launcher setup entry; authorization and destination changes use Settings → Actions.

## Routing

Local phrases include “提醒我”, “待办”, “别忘了”, “记得”, and common `todo` forms. Jev can suggest the same action for an intention to do something later. A fixed-time meeting belongs to Calendar instead.

## Execution

The original draft is interpreted locally, independently of optional AI body rewriting, style instructions, API keys, or network availability. The first line of the processed body becomes the title and remaining text becomes notes; unavailable rewriting falls back to the original body.

The panel displays the selected list and the exact due-date precision before confirmation:

- No time mentioned: “No due date”; no due components or alarm are added.
- A date without a time, such as “tomorrow buy milk”: a Gregorian year, month, and day only. Today remains valid throughout the day. No midnight, clock fields, or time zone are attached to this floating date.
- A complete date and time: the frozen instant and time zone, including seconds for an explicit “now” or a relative interval.

Supported expressions include full year-month-day dates, today/tomorrow/the day after tomorrow, this/next week with a weekday, Chinese and English clock times, and positive minutes or hours from the plan’s reference time. Relative times are converted once; Enter does not restart the interval.

Unclear, incomplete, invalid, conflicting, repeated, or unsupported time expressions block submission. Event ranges and durations require a single due time instead. No parsing failure defaults to an undated reminder or the current time. Correct the draft to an explicit value such as `2026-10-05 15:00 buy milk`; a blocked confirmation retains Reminders while editing that draft.

The result must be visible before confirmation. One Enter can then wait for body rewriting. Edits, target/configuration changes, dismissal, or expired plans cancel that pending confirmation; newly displayed plans require a new confirmation. Hover and VoiceOver expose the full destination and time zone.

Jotway writes the same frozen due value through EventKit. The support layer validates dates and time zones before any save, including callers that bypass the action. Success requires a confirmed reminder identifier. No notifications or repeat rules are added.

## Failure boundary

Missing destination, empty content, denied EventKit permission, or an unconfirmed write restores the draft. Jotway does not retain reminder state after a successful write.
