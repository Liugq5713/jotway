# Apple Calendar action

> Role: **Current**

Apple Calendar handles events with a concrete date or time. It becomes available after the user selects a calendar in Settings → Actions.

## Routing

Local phrases include “加到日历”, “记到日历”, “排个日程”, and “日程：”. Jev distinguishes a scheduled event from a task that merely needs a reminder.

## Time rules

The text processor may return a cleaned title/body plus start and end times.

- Missing start time falls back to the current time.
- Missing end time falls back to one hour after start.
- An end time not later than start also falls back to one hour after start.

Preparation resolves the time range once; confirmation executes that same prepared request.

## Execution and failure

Jotway writes through EventKit. Success requires a confirmed event identifier. Missing destination, empty content, denied permission, parsing failure that prevents a valid request, or an unconfirmed write restores the draft.

The created event belongs to Calendar; Jotway keeps no event history.
