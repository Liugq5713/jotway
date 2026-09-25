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
4. Press Enter or click the target to execute; Shift+Enter inserts a newline.

Without a usable Jev configuration or a local match, the default action handles the input. The factory default is Apple Notes; it still requires a configured Notes destination before it can write.

The usage guide demonstrates Apple Notes, Reminders, Calendar, Chrome search, and local application opening without executing examples automatically. It states that target switching with Option+Up/Down is available only when the current recognition state offers multiple targets. It also explains the plain-text input boundary, in-memory draft lifetime, default reminder/calendar times, and the distinction between intent recognition and per-action AI rewriting.

## Failure guidance

- Shortcut conflict: keep menu bar/Dock access visible and link to General settings.
- Missing action destination: keep the draft and link to the action's settings.
- Action failure: restore the submitted text; if a new draft already exists, retain the failed submission separately without overwriting the new draft. The current UI does not expose a recovery button for that retained submission.
- Missing Jev key: continue through local matching and the default action; recognition is optional.

Closing the panel is not proof of success. Completed content is viewed in its target application. Jotway has no browsable inbox or content history; confirmed routing may still retain the full draft locally as intent feedback.
