# Proposal

## Why

The user enabled macOS access, but Jotway Settings still reports that Accessibility is not allowed and selected webpage text does not reach the draft. The current Boolean status offers no way to tell a stale check from access that is unavailable to the running app, so repeating authorization gives no clear next step.

## What Changes

- Refresh passive Accessibility status when the user returns to Jotway, with a short bounded recheck and an explicit Check Again action.
- Describe an unsuccessful check as access unavailable to this running Jotway, rather than claiming the user never granted permission.
- Provide local recovery guidance for an unexpected running app location or access that remains unavailable after enabling it; never mark access granted based on the user's click alone.
- Keep Settings and the next shortcut capture consistent with a fresh process-level permission check. Keep browser support failures separate from permission failures.
- Preserve the current selection-only capture, draft, undo, clipboard, and 150 ms opening rules.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `selected-text-capture`: Add reliable permission refresh, honest status and recovery guidance for the running app, and consistent permission checks before capture.

## Impact

- `Sources/Integrations/Selection/SelectedTextPermission.swift`, `SelectedTextReader.swift`, `Sources/App/SettingsView.swift`, and the permission-result handling in `Sources/Window/PanelController.swift`.
- English and Simplified Chinese localized status and recovery text; `docs/product/settings.md` when implemented.
- Read-only app identity checks can use existing signing metadata. No new package, database migration, permission reset, automatic restart, signing change, or browser extension is proposed.
- Exact macOS failure is not yet reproduced in Jotway's own process. Browser identity is not needed to define the reported Settings bug; webpage compatibility acceptance must use an identified browser and harmless sample later.
