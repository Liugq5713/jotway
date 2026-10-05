# Settings

> Role: **Current**

Settings are organized by the user's decision, not by implementation module.

## Navigation

- **General**: appearance, panel placement, submission effect, global shortcut, launch at login, Dock visibility, and runtime logs.
- **Intent Recognition**: Jev key, connection test, local phrase rules, and local operation records.
- **AI**: AI source, model, key, connection test, and provider-specific fields.
- **Actions**: destination setup for Apple Notes, Reminders, and Calendar, plus Chrome and ChatGPT enablement.
- **Instructions**: manual AI instructions and prompts when the AI capability is present.
- **Getting Started**: a repeatable version of onboarding.
- **About**: version, update controls, download link, and contact link.

The sidebar groups configuration separately from help. Every page has a title and short description above a scrollable, grouped form. The window opens at 820 × 640 points, supports resizing down to 760 × 560, and limits form width on larger windows. Controls and surfaces follow the selected light, dark, or system appearance.

General settings group appearance, quick record behavior, startup, and diagnostics. Runtime-log controls are available in a collapsed disclosure group. Instruction editors keep restore-default on the left and cancel/save on the right; changes still require an explicit save.

Intent Recognition presents Jev in a compact service card with a saved-key badge, full-width masked key input, and an inline save or replace control. Connection testing and key removal sit below the input. The card keeps draft sharing and billing visible, with storage, test scope, and confirmation details in a collapsed disclosure. A saved-key badge confirms storage only; connection results appear separately. Key errors remain visible, and typing a replacement invalidates any previous connection result without replacing the saved key until Save or Replace is pressed.

Local Rules uses a matching compact card. Rules show saved prefix-to-action mappings above a full-width prefix input and a target menu with action icons. Enter adds a nonblank phrase for an enabled, ready action; if that target stops being available, the menu selects another available action or disables adding when none remain. Existing rules for disabled or temporarily unavailable actions remain visible and removable. Recent Corrections is not shown in Settings.

AI uses the same key input, status badge, and button styles in one service card. Registered sources appear as selectable tiles; bundled fixed-model names appear inside their tiles, while sources with model choices retain a model menu. Switching sources clears unsaved key input and refreshes that source's saved-key status. Sharing and billing remain visible; key storage and connection-test details are collapsed. AI tests include saved Instructions and report stale results separately when configuration changes during a test. Missing sources stay explicit and do not silently select another provider.

Jotway currently ships an English-only interface and does not expose a language setting or follow the macOS interface language. App-owned display copy, action labels, dynamic status, and safe errors are resolved from semantic keys in the English package resource. Stable IDs and machine state never store translated text. This resource boundary is the extension point for adding another language later without changing routing, persistence, or action configuration. User-authored text, destination names, and installed application names remain unchanged.

## Usage guide

Getting Started is a scrollable daily reference as well as a repeatable onboarding page. Its first section explains the complete input → target → confirmation flow and provides direct actions to open the quick record panel or configure Actions. The page shows the actual configured shortcut and conflict state, preserves shortcut editing and trial behavior, and links directly to Actions and Intent Recognition settings.

The guide covers Apple Notes, Reminders, Calendar, Chrome, local application opening, current keyboard behavior, plain-text input limits, optional intent recognition, Notes AI supplements and Reminder/Calendar body rewriting, in-memory draft lifetime, failure behavior, and the distinction between content in target applications and local operation records, including unsubmitted text. It never treats panel dismissal as success or promises a browsable local inbox. Opening or leaving the guide does not replace, submit, or clear the current draft.

## Action settings

The Actions page shows the bundled actions:

- Apple Notes requires a Notes destination and permission to execute and is the preferred fallback. It preserves the complete original draft and supports an optional fixed text tag, AI-generated related tags, and an independent AI Supplements switch with Supplement Preferences. Valid thinking assistance is appended separately; no useful or valid result means original text and fixed tags only.
- Apple Reminders requires a reminder list and has its own AI rewrite switch and style instruction. Rewrite controls the body only. Local time interpretation remains active; reminders without time intent have no due date, and date-only reminders retain that precision.
- Apple Calendar requires a calendar and has its own AI rewrite switch and style instruction. Rewrite controls the body only. Local time interpretation requires a clear start; an entirely unspecified end or duration defaults to one hour and is shown before submission.
- Chrome exposes an enable switch. When disabled, it is removed from recognition, selection, and routing.
- ChatGPT exposes an enable switch under Conversations. It opens a new desktop conversation with the draft prefilled for manual send. A compatible desktop application must be installed; missing installations keep their settings row and preferences but cannot execute. See [ChatGPT](../integrations/chatgpt.md).

The Actions page is generated from the registry's settings entries, including disabled, unconfigured, and temporarily unavailable modules. Labels, icon and tint, grouping, dynamic summary, enablement policy, and fallback marker all come from module declarations and state. Group titles use an optional resource key, falling back to the declared title. Storage actions appear as full-width, keyboard-accessible rows with their selected destinations. Selecting a row opens the module-provided detail page; navigation stores only the stable action ID, and the header's back button returns to the list. Chrome and ChatGPT expose their switches directly in the Search and Conversations sections, without detail pages. Long destination names wrap instead of being truncated.

Each unconfigured storage detail page offers Authorize to request macOS access. A successful authorized read keeps a valid saved destination; otherwise, Notes selects the default folder in its default account, Reminders selects the system default reminder list, and Calendar selects the system default calendar for new events. If the system default is unavailable, Notes tries another account's default folder before the first exposed folder, while Reminders and Calendar use the first writable destination. The destination is shown after authorization, and Change… opens an optional picker. No test content is written and no verification step is required.

Each storage module owns its authorization state, typed destination picker, content-assistance controls, and persistence adapter. The common settings host neither switches on concrete action IDs nor uses a generic configuration-field DSL. Notes supplement preferences affect only appended assistance; original text is protected by application assembly. Reminder and Calendar style text affects their body only. Time interpretation always reads the original draft locally, and unresolved times require an edit before saving. A user-selectable default action is not implemented; the ready module with the lowest declared fallback priority wins, currently Notes, then Reminders, then Calendar. If no storage action is ready, the launcher offers Set Up Notes rather than executing another kind of action.

The launcher’s Set Up Notes window offers Authorize and explains that the default location can be changed in Settings; its folder picker is available only from the settings detail page. Opening either view does not request permission; the user explicitly clicks Authorize. Background typing and prewarming do not request permission. Successful authorization completes launcher setup automatically and returns to the original text and selection, waiting for another Enter to save. Cancelling also returns to the original draft. Reminders and Calendar use their settings detail pages and do not provide launcher setup entries.

Denied or revoked authorization preserves the saved destination. When authorization or a destination needs repair, the page replaces Change… with Authorize Again and shows a link to the relevant System Settings privacy controls. The link is hidden when no repair is needed. For Notes, the path is Privacy & Security → Automation → Jotway → Notes. Permission errors retain their meaning instead of appearing as an empty destination list. The app does not reset system permissions or automatically retry an uncertain write.

After all bundled modules are registered, Jotway removes saved rules and `actionEnabled.*` keys whose action ID is no longer registered. A registered action keeps its preferences when the user disables it or its external destination is temporarily unavailable. Existing destination, tag, enablement, and rule preferences retain their encoding and values. Notes keeps the existing AI enable state and tag preferences, while legacy rewrite styles remain stored but inactive. A separate supplement-preference key starts with the new defaults and is never overwritten by reopening or migration; settings indicates when an old style was not carried over. Reminder and Calendar rewrite keys retain their meaning.

## Persistence and secrets

- Ordinary preferences, action enablement, rewrite instructions, Notes supplement preferences and tag options, and selected destinations use `UserDefaults`.
- AI and Jev keys are stored in local per-user files with restricted permissions and are not echoed back in the UI.
- Local operation records include stable unsubmitted text and key routing/execution observations. Intent Recognition settings controls capture, retention (90 days by default), manual JSONL/CSV export, storage and completeness status, and clear. Turning capture off also deletes existing records. Rules, application usage, and technical logs are unaffected.
- Operation records never automatically update Local Rules or restore editable drafts after restart.
- Changing a source, model, or prompt invalidates stale connection-test conclusions.

## Connection tests

Connection tests use fixed sample content. They do not send the current draft. A successful connection proves reachability and response shape, not production recognition quality.

## Runtime logs

General settings can open, export, or clear runtime logs. Export includes the current Jev rule definition so a diagnostic bundle remains interpretable. See [Runtime logs](../development/runtime-logs-research.md).
