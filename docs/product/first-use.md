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

Skipping onboarding does not disable the launcher. Settings → Quick Guide remains a repeatable guide for opening the panel, confirming a target, changing the shortcut, configuring actions, and managing local operation records.

## First action

The shortest successful path is:

1. Open the panel.
2. Type a short sentence.
3. Check the target shown at the bottom of the panel. Use Option+Up/Down to change it if needed.
4. Press Enter or Command+Enter in the editor. A ready action executes; Set Up Notes opens configuration. Shift+Enter inserts a newline.

Without an explicit target, action keyword or local application match, Notes handles ordinary text immediately. If Notes is not ready, the panel shows Set Up Notes. Typing and routing do not request a model. Notes also remains selectable directly or through a local Notes prefix.

Opening Set Up Notes preserves the text and selection and shows an Allow Access button. The user clicks Allow Access and grants macOS access; Jotway keeps an available saved folder or selects the default folder in the default Notes account. If needed, it tries another account's default folder before the first exposed folder. Successful authorization completes setup and returns to the original draft; cancelling also returns without submitting. After completion, check Save to Notes and press Enter again to save. Setup does not write a test note or require verification. Configuration alone never submits or clears the draft.

Settings → Apps offers direct Notes authorization. Existing valid destinations are retained. Change… optionally selects another folder in Notes settings; the launcher setup window has no picker. Opening either view alone never prompts for permission.

For a reusable starting point, type `@` at the start of a single-line draft and choose a template. The built-in templates initially use the names 记录想法 and 梳理问题; Settings → Templates edits built-ins and manages custom definitions. Selection replaces the query and preserves the target without submitting. Tab and Shift+Tab move through fields, Esc ends filling, and Undo restores the query and its selection. Choose Apple Notes or Codex through the target menu or keyboard cycle; Let Jotway Choose restores automatic routing, including local application matching. Former action prefixes remain literal text.

The usage guide demonstrates Apple Notes and local application opening without executing examples. For a nonempty draft, Tab focuses the target capsule and Return or Space opens its menu; clicking it has no action. A chosen target follows edits and reopening; Let Jotway Choose releases it. Option+Up/Down cycles available Notes and Codex targets. The guide distinguishes local matching from optional Notes AI supplementation, and explains plain-text input, in-memory drafts and operation-record retention.

Ordinary preparation failures remain visible with the draft. If preparation is running, one Enter waits; edits, target/configuration changes, composition and hiding the panel cancel that pending confirmation. No time preview is required.

## Failure guidance

- Shortcut conflict: keep menu bar/Dock access visible and link to General settings.
- Missing Notes destination: use Set Up Notes from the panel or Settings → Apps, retaining the draft.
- Storage permission denied or revoked: retain the selected destination, open the linked System Settings privacy controls, then use Allow Access Again. Notes uses Privacy & Security → Automation → Jotway → Notes. Jotway does not reset system authorization.
- Action failure: restore the submitted text and routing mode; if the new draft has been edited or its routing changed, retain the failed submission separately without overwriting it. The current UI does not expose a recovery button for that retained submission.

Closing the panel is not proof of success. Completed content is viewed in its target application. Jotway has no browsable inbox or content history; local operation capture retains full stable text, including unsubmitted input. Quick Guide explains this scope and links to General → Troubleshooting for capture, retention, export, and deletion; records never restore drafts after restart.
