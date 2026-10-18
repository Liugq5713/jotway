# Settings

> Role: **Current**

Settings are organized by the user's decision, not by implementation module.

## Navigation

- **General**: Quick Entry (shortcut, Selected Text, screen and Chrome source), Notifications, Startup (login and Dock), then Diagnostics.
- **Appearance**: Color Theme (Follow System, Light, or Dark), followed by Finish Animation.
- **App Suggestions**: local operation records, retention, export and clearing.
- **AI Services**: current text service, Jotway AI activation and quota, one personal model.
- **Templates**: editable built-ins and local custom writing templates.
- **Apple Notes**: direct access to save destination, daily grouping, AI insights and review settings. No app-list step.
- **Writing Preferences**: automatic thinking prompts, Notes Idea Preferences, and background instructions when the AI capability is present.
- **Quick Guide**: a repeatable version of onboarding.
- **About**: version, update controls, download link, and contact link.

Labels use one to four familiar words. Ordinary descriptions stay within 20 words; privacy, billing, deletion, and essential steps use short sentences without omitting consequences. App names, keyboard shortcuts, and user text keep their original form. AI prompts and saved note section headings retain their existing wording.

The sidebar groups configuration separately from help. Every page has a title and short description above a scrollable, grouped form. The window opens at 820 × 640 points, supports resizing down to 760 × 560, and limits form width on larger windows. Controls and surfaces follow the selected light, dark, or system appearance.

Appearance applies immediately to the settings window, quick record panel, native editor, and other Jotway windows. Follow System remains the default and tracks the Mac's appearance; Light and Dark override it for Jotway. The existing `themeMode` preference preserves the choice across launches and keeps previously saved selections. Choices support keyboard focus and activation, and expose their selected state to assistive technology. Finish Animation follows Color Theme and retains the native Drift Away / Fly Away menu and Reduce Motion help. It uses the original app-level `submissionEffect` binding, `wind` / `ufo` encoding and Drift Away default; moving the control changes neither runtime animation nor Completion Notifications.

General groups controls in this order: Quick Entry contains the keyboard shortcut, its conflict/recommendation feedback, Selected Text, Use Pointer's Screen and Chrome Source; Notifications contains Completion Notifications; Startup contains Open at Login then Show Dock Icon with its issue message; Diagnostics contains the initially collapsed App Logs controls. Instruction editors keep restore-default on the left and cancel/save on the right; changes still require an explicit save.

Completion Notifications is a single switch for all actions and defaults to off. The `completionNotificationsEnabled` preference persists across launches and is checked when a result arrives, including tasks already running when the setting changes. Turning it off suppresses completion popups without replaying those successes at the next panel opening. Execution, failure recovery, and the recent Codex task list remain available.

App Suggestions contains only Local Records. There is no intent-service key, connection test, model readiness or billing card. Local application matching needs no credential. Legacy Jev credential files and unrelated preferences are neither read nor removed.

Local Records defaults to a capture switch, a short disclosure that includes unsent drafts, an Export Records button, and collapsed Manage Records. The disclosure contains retention days (unchanged 1–3650 range and 90-day default), space, counts, pending writes and Clear Records. Re-entering the page resets only the disclosure state. Healthy integrity is silent; missing/unknown integrity, unavailable statistics, busy state, operation results and Show Exported Files stay outside the fold. Export cancellation restores controls. Stop-and-delete and clear retain separate confirmations; cancellation preserves capture and records.

Your Phrases has no settings entry or runtime effect. Existing `intentRules` data remains unchanged but is not loaded, edited or considered effective action configuration. Historical operation records retain their rule sources and snapshots.

AI Services starts with the current text service (Jotway AI, Personal Model, or Not Configured), followed by Jotway AI activation and quota. A stored code takes priority for every text request, including connection tests; invalid, disabled, depleted or unreadable codes never fall back to personal credentials. Activating or replacing a code preserves personal settings. Remove Code explains that subsequent requests resume the saved personal model. Account refresh and quota state retain their credential-scoped behavior. See [AI capability](../plugins/ai.md#jotway-ai-activation).

The Personal Model section contains one service type (Claude or OpenAI-compatible), HTTPS API Base URL, Model ID and masked API Key, plus Save, Remove Key and Test Connection. There are no primary/fallback, swap, or separate fast/deep selectors. Claude selection pre-fills its official base URL. Changing protocol or address requires re-entering the key; same-address model edits may retain it. The active service handles all text features. A stored Jotway code leaves the personal form editable but inactive, collapsed by default and marked saved but not in use. Without a code, the personal form starts expanded. An explicit notice identifies the connection-test target. Tests use a fixed sample and deep streaming, and are disabled until edits are saved; edits, effective configuration changes or leaving the view cancel old results. Notes grouping links to this page instead of duplicating credential forms. No history-search or embedding model configuration is offered.

Writing Preferences offers Automatic follow-up prompts, off by default. The independent Boolean preference survives restart; prompts and drafts do not. Its disclosure explains that a writing pause sends the current draft to the active AI service, and a prompt appears only when it can help the user think further. Automatic checks, empty results and failures stay silent. Turning it off stops automatic work and keeps the manual footer entry available. It does not change Notes Add Extra Ideas or model selection. See [Thinking prompts](../../openspec/specs/draft-thinking-prompts/spec.md).

Jotway currently ships an English-only interface and does not expose a language setting or follow the macOS interface language. App-owned display copy, action labels, dynamic status, and safe errors are resolved from semantic keys in the English package resource. Stable IDs and machine state never store translated text. This resource boundary is the extension point for adding another language later without changing routing, persistence, or action configuration. User-authored text, destination names, and installed application names remain unchanged.

## Usage guide

Existing action-specific settings requests can still open the Codex detail page; Back returns to Apple Notes. Set Up Codex opens a one-time installer in Terminal after the user has installed and signed into Codex CLI. The installer copies the bundled helper into the user's Application Scripts folder; it leaves a different existing helper untouched. Check Setup refreshes its availability. Subsequent tasks run in the background without opening Terminal or selecting a project. See [Codex](../integrations/codex.md).

Quick Guide is a scrollable daily reference as well as a repeatable onboarding page. Its first section explains the complete input → target → confirmation flow and provides direct actions to open the quick record panel or configure Apple Notes. The page shows the actual configured shortcut and conflict state, preserves shortcut editing and trial behavior, and links directly to Actions and App Suggestions settings.

The guide covers templates, Apple Notes, local application opening, remaining explicit actions, keyboard behavior, plain-text input limits, optional Notes AI supplements, in-memory drafts and failure recovery. Content belongs to target applications; local operation records can retain unsubmitted text. Dismissal is not success. Opening or leaving the guide does not replace, submit or clear a draft.

## Action settings

The independent Templates page shows the two built-in templates first, initially named “记录想法” and “梳理问题”. Each template displays its name above its multiline body. Built-ins enter editing in their existing row and return there after Save or Cancel, keeping their stable identity and fixed order; they cannot be deleted. Custom templates follow creation order, with edit and delete controls below their content, and keep their new/edit form below the list. One pending edit disables all Add, Edit and Delete controls until it is saved or cancelled. Each form places Name above the single-line field, then Body above the full-width multiline editor, with labels, fields and Save/Cancel aligned left. A failed save keeps the entered text and shows the reason in that form; Cancel leaves the saved version untouched. Inline editing focuses the name field and retains Command+S and Esc. Detailed editing and protection rules are in [Input templates](../../openspec/specs/input-templates/spec.md). Apple Notes configuration is available directly from the sidebar.

Names are trimmed, single-line, nonempty and unique ignoring case across built-in and custom templates. Bodies must expand to non-whitespace text. Supported markers are `${n}`, `${n:default}` and at most one `${0}`; positive numbers are unique, have no leading zero and are visited numerically. Escape a dollar with `\$`, a backslash with `\\`, or a default-value closing brace with `\}`. `$1` stays literal. Unsupported syntax shows its UTF-16 position and preserves the editor and previous saved definition.

Template definitions use the versioned `inputTemplates.v1` local UserDefaults value. Custom definitions retain stable UUIDs and list order; optional `builtInOverrides` preserve edited built-in names and bodies across launches without turning them into custom items. Existing custom-only values remain readable, and unedited built-ins use their bundled defaults. A corrupt or incompatible value remains untouched: an error is shown, bundled built-ins remain usable and all template writes are disabled. A failed write keeps the previous valid value and reports an error. Definition storage never contains draft text or filling sessions. Legacy action-mention visibility/order keys remain stored but are not read or written by the runtime.

The Apple Notes sidebar entry opens its grouped settings form directly. Existing action-specific settings requests still resolve by stable action ID and may temporarily show another module's detail page; the back button returns to Apple Notes. No generic app list is shown.


Notes offers Allow Access to request macOS Automation access. A successful authorized read keeps a valid saved destination or selects the default folder in the default account, then another account’s default folder or the first exposed folder. Change… opens the optional picker. Setup writes no test content and needs no verification step.

Notes owns authorization, the typed folder picker, assistance controls and persistence. The common settings host uses module declarations. Supplement preferences affect only appended assistance; original text is protected by application assembly. Notes is the only bundled fallback; if it is unavailable, Set Up Notes appears instead of dispatching another action.

The launcher’s Set Up Notes window offers Allow Access and explains that the default location can be changed in Settings; its folder picker is available only from the settings detail page. Opening either view does not request permission; the user explicitly clicks Allow Access. Background typing and prewarming do not request permission. Successful authorization completes launcher setup automatically and returns to the original text and selection, waiting for another Enter to save. Cancelling also returns to the original draft.

Denied or revoked authorization preserves the saved destination. When authorization or a destination needs repair, the page replaces Change… with Allow Access Again and shows a link to the relevant System Settings privacy controls. The link is hidden when no repair is needed. For Notes, the path is Privacy & Security → Automation → Jotway → Notes. Permission errors retain their meaning instead of appearing as an empty destination list. The app does not reset system permissions or automatically retry an uncertain write.

Unknown and retired action preferences remain stored and inactive; no cleanup migration removes them. Registered modules keep preferences while disabled or unavailable. Notes keeps its AI enable state, folder, tag values and inactive legacy rewrite styles. Automatic fixed and AI tags remain paused. Separate supplement preferences are never overwritten by reopening settings.

## Persistence and secrets

- Template definitions, ordinary preferences, action enablement, rewrite instructions, Notes supplement preferences and tag options, and selected destinations use `UserDefaults`.
- Personal AI provider keys and Jotway AI activation codes are stored in local per-user files with restricted permissions; neither uses the Keychain. Neither is echoed back in the UI.
- Local operation records include stable unsubmitted text and key routing/execution observations. App Suggestions settings controls capture, retention (90 days by default), manual JSONL/CSV export, storage and completeness status, and clear. Turning capture off also deletes existing records. Inactive legacy rule preferences, application usage, and technical logs are unaffected.
- Operation records never automatically change routing or restore editable drafts after restart.
- Changing a source, model, or prompt invalidates stale connection-test conclusions.

## Connection tests

Connection tests use fixed sample content. They do not send the current draft. A successful connection proves reachability and response shape, not answer quality.

## Runtime logs

General settings can open, export, or clear runtime logs. Export retains raw log lines, including historical Jev metadata, without generating a current routing-rule file. See [Runtime logs](../development/runtime-logs-research.md).

Apple Notes contains a separate Notes Review switch and folder scope. Today/weekly reviews read recent original text on demand from authorized folders, preserving an existing custom scope. There is no background indexing, Search History inspector or embedding service. Bounded review excerpts go to the active text AI service.

Chrome Source defaults to off and is independent of action routing and clipboard history. Enabling it or selecting Allow Chrome Access requests macOS automation permission. Passive checks and copy observations never request permission. The status and retry control remain visible when enabled; denial leaves plain text capture available. Disabling discards unused source candidates but does not remove draft text already shown. The disclosure explains that the current page near a copy may not be the exact source, links may contain private details, and attribution follows existing draft processing settings.

## Clipboard

Actions → Clipboard provides a collection toggle, local-storage disclosure, and a separately confirmed Clear clipboard history button. The history list has no settings navigation; use this application settings page to manage it. Collection defaults on only when no preference is saved, including for users upgrading without a saved choice. Existing enabled and disabled choices stay unchanged across restarts, and turning off default collection persists. Collection remains independent of action enablement and template settings. Enabling starts from the current clipboard version; it does not backfill old copies. Disabling stops collection and OCR without deleting existing history. Clearing removes original text/images, thumbnails and OCR, but leaves the current clipboard unchanged. Storage errors pause collection and remain visible; toggling collection retries the store.

Search and copy remain available with collection off. Images can be searched by cached recognized text. Confirmation copies the original representation; it does not paste into another application.

## Selected Text permission

General → Quick Entry shows Selected Text immediately after shortcut feedback. It explains the supported-control scope and shows passive Accessibility status, an explicit Allow Accessibility button when needed, and a System Settings link. Returning to settings refreshes status; it never reads an old selection. There is no separate capture toggle or shortcut. Ordinary recording remains available without permission, with a nonblocking notice that does not overwrite an existing error. Notes and Chrome keep their own permissions. See [Selected text](../../openspec/specs/selected-text-capture/spec.md) and [General settings](../../openspec/specs/general-appearance-settings/spec.md).
