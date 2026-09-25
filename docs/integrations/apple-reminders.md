# Apple Reminders action

> Role: **Current**

Apple Reminders handles task-like input. It becomes available after the user selects a reminder list in Settings → Actions.

## Routing

Local phrases include “提醒我”, “待办”, “别忘了”, “记得”, and common `todo` forms. Jev can suggest the same action for an intention to do something later. A fixed-time meeting belongs to Calendar instead.

## Execution

The text processor may return cleaned text and a due date. The first line becomes the reminder title and remaining text becomes notes. When no due date is produced, the current implementation falls back to the current time.

Jotway writes the reminder through EventKit to the selected list. Success requires a confirmed reminder identifier.

## Failure boundary

Missing destination, empty content, denied EventKit permission, or an unconfirmed write restores the draft. Jotway does not retain reminder state after a successful write.
