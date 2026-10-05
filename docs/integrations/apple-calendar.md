# Apple Calendar action

> Role: **Current**

Apple Calendar handles events with a concrete date or time. It becomes available after authorization and destination setup in Settings → Actions.

## Authorization and destination

Clicking Authorize requests macOS access to Calendar. Opening the action settings page, typing, and action prewarming do not request permission. After authorization, Jotway keeps an available writable saved calendar; otherwise, it selects the system default calendar for new events, falling back to the first writable calendar if needed. Change… lets the user optionally choose another calendar. No test event or verification step is required.

Denied or revoked authorization preserves the saved calendar. When authorization or the destination needs repair, the page offers a link to System Settings plus Authorize Again. Successful authorization restores availability when a writable destination exists. Calendar has no launcher setup entry; authorization and destination changes use Settings → Actions.

## Routing

Local phrases include “加到日历”, “记到日历”, “排个日程”, and “日程：”. Jev distinguishes a scheduled event from a task that merely needs a reminder.

## Time rules

The original draft is interpreted locally, independently of AI body rewriting, style instructions, API keys, or network availability. The panel shows the selected calendar and the absolute start and end before confirmation. Hover or VoiceOver exposes the full destination and frozen time zone.

A full date and time is required. Supported expressions include full year-month-day dates, today/tomorrow/the day after tomorrow, this/next week with a weekday, Chinese and English clock times, and positive minutes or hours from the plan’s reference time. “Now” must be explicit. Relative times are converted once and do not restart when Enter is pressed.

- A clear start with no mention of an end or duration receives one hour. The result includes the end and “1 hr default”.
- Explicit ends and durations must parse completely, agree, and end after the start. Cross-day ranges require both dates.
- No time, date-only input, partial dates, ambiguous wording, conflicting or repeated times, unsupported time-zone words, invalid dates, and ambiguous or nonexistent daylight-saving times block submission. They never become “now”, midnight, a different day, or a repaired duration.

Correct blocked input directly in the draft, for example `2026-10-05 15:00 meeting`. A blocked confirmation retains Calendar while that draft is corrected. A valid result must actually be visible before confirmation; one Enter can then wait for optional body rewriting. Edits, target/configuration changes, dismissal, or expired time plans cancel that pending confirmation. A newly displayed plan needs a new confirmation.

The plan freezes the destination and time range. EventKit receives those same values and independently rejects incomplete or invalid schedules before any save. Body rewriting can fall back to the original text without changing the schedule.

## Execution and failure

Jotway writes through EventKit. Success requires a confirmed event identifier. Time and preparation failures leave the draft in place. Missing destination, empty content, denied permission, or an unconfirmed write preserves or restores the draft.

The created event belongs to Calendar; Jotway keeps no event history.
