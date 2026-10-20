# Design

## Context

See proposal.md for the user report. The user confirmed that the incorrect status is in Settings after enabling permission.

Observed source behavior:

- `SelectedTextPermission` starts with `granted = false`. It calls `AXIsProcessTrusted()` on refresh, and requests permission only from its explicit action. Requesting access immediately refreshes once.
- `SettingsView` refreshes on appearance and `NSWindow.didBecomeKeyNotification`. It has no application-activation refresh, bounded retry, explicit recheck, or recovery explanation. This is a gap, not proof that the callback is the reported failure.
- `SelectedTextReader` independently checks `AXIsProcessTrusted()` before reading only the focused element's selected text. The controller handles `.unauthorized` separately, but discards other failure detail. No browser capability result currently explains a false Settings permission status.
- Shortcut capture starts before focus changes and has a shared 150 ms source-preparation budget. Preserve this path and its protections.
- Existing tests cover editor quotation behavior, but the inspected tests contain no focused permission recovery coverage. Do not add tests without a separate user request; use isolated verification and existing checks.

Read-only environment evidence during planning: running Jotway uses an `AppTranslocation` bundle path. That bundle and `/Applications/Jotway.app` have the same bundle ID, version, build and ad-hoc designated code-hash requirement. This does not establish a mismatch or a TCC failure. No permission database, webpage contents, clipboard or live app UI was read. Trust was not measured inside Jotway; checking from a shell helper would measure the helper, not prove Jotway's state.

Apple documents [the trust API](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions) as a check of the current process. [Code-signing requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements) explain application identity. Use these facts without assuming that translocation or ad-hoc signing alone proves the cause.

## Goals / Non-Goals

**Goals:** Make the status check fresh, observable, truthful and recoverable; keep the permission result used by capture consistent with Settings; verify the reported failure from the owning process when manual acceptance is available.

**Non-Goals:** Universal browser support, DOM extraction, simulated Copy, whole-control text or AX tree scans, new permissions, TCC database access/reset, automatic relaunch, installation or signing changes. Do not treat a recovery message as proof that capture now works.

## Decisions

### 1. Keep one passive permission check contract

Keep the injectable trust-check seam and current-process API. The observable MainActor permission model owns the latest check state and bounded refresh generation. The reader must still check fresh permission before capture; publish its permission observation back on the MainActor without letting an older result override a newer check. Do not make the worker reach into UI state synchronously.

Represent checking separately from the last result. Use wording such as “This Jotway cannot access selected text yet” for a false check. A click on Allow is not a grant. Keep request and passive-check closures separate. Reject storing an authorized Boolean in preferences or treating any successful browser operation as equivalent to current-process trust.

### 2. Refresh across the permission round trip

Retain window/appearance refresh and add application activation while Settings is visible. Start one cancellable sequence with an immediate check and short delayed checks, ending within three seconds (for example at 0, 0.25, 0.75 and 1.5 seconds). Stop on success, disappearance or replacement by a newer sequence. Check Again uses this passive sequence; Allow requests once and then starts it.

This addresses missed UI events and delayed availability. It does not claim to repair a process-level cached denial. Avoid continuous background polling and private permission notifications. The shortcut does one fresh check and keeps its existing deadline; it never waits for the Settings retry sequence.

### 3. Give recovery steps without inventing a diagnosis

Show Check Again next to the current permission actions. When unavailable, give a short disclosure: verify the Jotway entry in macOS Accessibility, check the running copy, then retry. Make `Bundle.main.bundleURL` available locally for identifying the copy. If it is an AppTranslocation path, explain that this is a temporary running location and suggest the intended installed copy. Do not label it a proven permission mismatch.

If a manual relaunch is suggested, first tell the user to copy any unsaved draft because drafts do not survive restart. Do not add a restart button or an automatic migration. Keep details out of normal capture; use existing localized settings styles and keyboard accessibility. No app path or selected text is added to runtime logs.

### 4. Keep permission and selection outcomes separate

Audit the controller's unauthorized branch and permission notice ownership. A fresh grant clears only an obsolete permission notice, never an unrelated error. A fresh denial updates permission status. Empty, unsupported, failed, busy and timed-out selection reads cannot set permission to false. Preserve quotation adoption, deduplication, clipboard priority, cancellation and marked-text guards.

Reject broader browser fallback as part of this fix: the confirmed report concerns Settings access, and current specs forbid simulated copy and full-text extraction.

## Risks / Trade-offs

- A running process may remain untrusted after UI refresh → show truthful recovery guidance; require manual grant/relaunch acceptance before claiming the user's failure is fixed.
- Temporary path or ad-hoc signature may be unrelated → treat both as context only; no automatic signing or quarantine changes.
- Fast activation and revocation events may race → cancel older generations and verify that a late result cannot restore stale success.
- Browser controls may not expose selected text after access works → validate a known sample in an identified browser and report this separately from permission recovery.

## Migration Plan

No stored-data migration. Implement within the current selection and settings modules, then update Current settings documentation and sync the delta when complete. Build and verify without launching the real app by default. Real permission toggles, relaunch and webpage capture remain manual acceptance unless separately requested. Rollback removes the refresh/recovery additions without altering macOS permission records or saved preferences.

## Open Questions

- During manual acceptance, does Jotway's own trust check stay false after returning to Settings, or does the check become true while the UI remains false? This selects the relevant recovery branch without changing the contract.
- Which browser/control should be used for the user's final webpage capture check? Use harmless selected text and record the browser/version in the handoff, not in Current docs.
