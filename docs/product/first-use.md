# First use

> Role: **Current**

First use should end when the user has opened the quick record panel and successfully executed one action. It is not a tour of every feature.

## Entry points

- The configured global shortcut is the fastest entry.
- The menu bar and Dock remain recovery paths.
- Applications or Spotlight can reopen Jotway when neither icon is visible.

The default shortcut is only a recommendation. Jotway reports registration conflicts and lets the user choose another combination.

## Welcome and shortcut trial

The welcome experience explains the input, target confirmation, and execution flow in one sentence, offers shortcut setup, and lets the user try the shortcut from another application. A trial only succeeds after Jotway observes that the user left the app and returned through the configured shortcut.

Skipping onboarding does not disable the launcher. Settings → 使用入门 remains a repeatable guide for opening the panel, confirming a target, changing the shortcut, configuring actions, and revisiting intent-recognition settings.

## First action

The shortest successful path is:

1. Open the panel.
2. Type a short sentence.
3. Check the target shown at the bottom of the panel, clicking its name to change it if needed; for Reminders and Calendar, also check the destination and exact time result.
4. Press Enter or Command+Enter in the editor. A ready action executes; Set Up Notes opens configuration. Shift+Enter inserts a newline.

Without a usable Jev configuration or a local match, a ready default action handles the input. Apple Notes is preferred when configured and available, followed by Reminders and Calendar. If none is ready, the panel shows Set Up Notes, including while recognition is pending or fails. Notes also remains selectable directly or through a local Notes prefix.

Opening Set Up Notes preserves the text and selection and shows an Authorize button. The user clicks Authorize and grants macOS access; Jotway keeps an available saved folder or selects the default folder in the default Notes account. If needed, it tries another account's default folder before the first exposed folder. Successful authorization completes setup and returns to the original draft; cancelling also returns without submitting. After completion, check Save to Notes and press Enter again to save. Setup does not write a test note or require verification. Configuration alone never submits or clears the draft.

Settings → Actions offers the same direct authorization for Notes, Reminders, and Calendar. Reminders defaults to the system reminder list and Calendar to the system calendar for new events, with a writable fallback if needed. Existing valid destinations are retained. Change… optionally selects another location in each action's settings; the Notes launcher setup window has no picker. Opening an action settings page or the setup window alone never prompts for permission.

The usage guide demonstrates Apple Notes, Reminders, Calendar, Chrome search, and local application opening without executing examples automatically. Clicking the target name opens the candidate menu; the same button shows Choose Target or an explicit choice before typing and remains available with a single candidate. A chosen target follows edits and panel reopening; Use Automatic releases it. Option+Up/Down cycles available targets without including Use Automatic. It also explains the plain-text input boundary, in-memory draft lifetime, local time interpretation, undated and date-only reminders, the explicit Calendar start requirement and displayed one-hour default duration, and the distinction between intent recognition, Notes AI supplements, and Reminder/Calendar body rewriting.

For Reminders and Calendar, correct unclear time directly in the draft before saving. Calendar requires a date and time; a reminder can have no due date or only a date. A valid result must appear before Enter can submit. If body preparation is still running, one Enter waits; editing, changing the target, or hiding the panel cancels that pending confirmation.

## Failure guidance

- Shortcut conflict: keep menu bar/Dock access visible and link to General settings.
- Missing Notes destination: use Set Up Notes from the panel or Settings → Actions, retaining the draft. Reminders and Calendar use Authorize in their action settings.
- Storage permission denied or revoked: retain the selected destination, open the linked System Settings privacy controls, then use Authorize Again. Notes uses Privacy & Security → Automation → Jotway → Notes. Jotway does not reset system authorization.
- Action failure: restore the submitted text and routing mode; if the new draft has been edited or its routing changed, retain the failed submission separately without overwriting it. The current UI does not expose a recovery button for that retained submission.
- Missing Jev key: continue through local matching and the default action; recognition is optional.

Closing the panel is not proof of success. Completed content is viewed in its target application. Jotway has no browsable inbox or content history; local operation capture retains full stable text, including unsubmitted input. Getting Started explains this scope and links to Intent Recognition settings for capture, retention, export, and deletion; records never restore drafts after restart.
