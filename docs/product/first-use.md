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
3. Check the target shown at the bottom of the panel.
4. Press Enter or click the target. A ready action executes; Set Up Notes opens configuration. Shift+Enter inserts a newline.

Without a usable Jev configuration or a local match, a ready default action handles the input. Apple Notes is preferred when configured and available, followed by Reminders and Calendar. If none is ready, the panel shows Set Up Notes, including while recognition is pending or fails. Notes also remains selectable directly or through a local Notes prefix.

Opening Set Up Notes preserves the text and selection while it opens the authorization and folder picker. The user grants access, selects a folder, and explicitly chooses Verify and Finish; the UI explains that verification creates a fixed test note, not the draft. Completing or cancelling returns to the original draft. After completion, check Save to Notes and press Enter again to save. Configuration alone never submits or clears the draft.

The usage guide demonstrates Apple Notes, Reminders, Calendar, Chrome search, and local application opening without executing examples automatically. It states that target switching with Option+Up/Down is available only when the current recognition state offers multiple targets. It also explains the plain-text input boundary, in-memory draft lifetime, default reminder/calendar times, and the distinction between intent recognition and per-action AI rewriting.

## Failure guidance

- Shortcut conflict: keep menu bar/Dock access visible and link to General settings.
- Missing Notes destination: use Set Up Notes from the panel or Settings → Actions, retaining the draft. Other missing destinations keep their existing action settings flow.
- Notes permission denied or revoked: retain the selected folder, follow System Settings → Privacy & Security → Automation → Jotway → Notes, then read folders again. Jotway does not reset system authorization.
- Action failure: restore the submitted text; if a new draft already exists, retain the failed submission separately without overwriting the new draft. The current UI does not expose a recovery button for that retained submission.
- Missing Jev key: continue through local matching and the default action; recognition is optional.

Closing the panel is not proof of success. Completed content is viewed in its target application. Jotway has no browsable inbox or content history; confirmed routing may still retain the full draft locally as intent feedback.
