# Design

## Context

See proposal.md for the product scope and the user's confirmed retained features.

The current working tree has two supplement entry paths. `AppleNotesModule.makeAction()` injects a deep `NotesSupplementProcessor` into ordinary saves. `AppleNotesAction.prepare()` waits for that optional result before preparing the write. Grouped saves use `NotesDailyGroupingCoordinator.scheduleRefresh()` after original confirmation; `resume()` can start refresh work again after restart. The same coordinator also owns the FIFO write queue, candidate cache, uncertain-write reconciliation and initial-title recovery, which must survive.

`NotesDailyDocument.render(supplement:)` creates generated sections. Its `renderRetainingGenerated(coveredAt:)` adds a stale-analysis notice, so simply reusing that method would still create new AI-related content. Also, the current `supplementsEnabled == false` append path drops old generated content. Setting the flag permanently false is therefore not sufficient.

`NotesDailyGroupingStore.Pending.Kind.refresh`, `Snapshot.generatedRevision`, complete boundary fingerprints and `NotesOriginStore` encode existing data. Reviews depend on these original/generated boundaries. The source-link handler is independent of new supplement generation.

The settings live in `Sources/Actions/Settings/ActionSettingsView.swift` and the Writing Preferences section of `Sources/App/SettingsView.swift`. Existing tests in `LauncherActionTests` cover original whitespace, literal action-like text, HTML rendering, one create, and supplements; `AITextProcessorTests` only covers the removed processor. This tree already includes unrelated edits to these areas.

## Goals / Non-Goals

**Goals:** Remove the feature from the call graph, simplify save preparation, and keep existing saved data readable. Make legacy compatibility unable to generate new insights.

**Non-Goals:** No model-provider redesign, new persistent body storage, history cleanup, tag feature, review redesign, or title-policy change. Title recovery remains an allowed write to an existing note; “only grouping changes note bodies” does not mean removing that confirmed exception.

## Decisions

### 1. Remove supplement production at its callers

Remove processor construction, supplement preparation/deadline, deep invocation snapshots used only for saving, refresh closures/tasks/revisions and post-save refresh scheduling from the Notes module/action/coordinator. Ordinary saves go directly through existing title resolution and original-only rendering. Preserve destination validation, original submission identity and completion receipts.

Keep the shared model runtime and deep streaming because reviews still need them. Remove supplement-only processors/results and logging fields only after checking references; historical diagnostic decoding or shared types can remain when compatibility requires them. Do not replace production removal with a hidden always-off toggle: that leaves an unnecessary caller path and risks activation by old preferences.

### 2. Keep legacy reads and reconciliation separate from generation

Retain decoding of old generated boundaries, generated revision fields and pending refresh kinds. No new `.refresh` record is created. A legacy pending refresh can be confirmed from matching readback, using existing reconciliation rules, but never reissued. Unresolved writes stay protected; do not delete their evidence or treat them as permission to overwrite.

Keep title startup/recovery independent of the former refresh gate. Do not retain startup candidate scans just to check for generation work that no longer exists; reconcile when the surviving safe-write/title flows require it. Preserve the same-day scope and FIFO write guards.

Deleting old fields immediately would break decoding or lose uncertain-write evidence. A database cleanup migration is unnecessary for this change.

### 3. Preserve old tails without adding analysis metadata

New documents render only titles, originals and applicable timeline metadata. For a verified legacy append, recover the full boundary parts and retain the generated tail and any existing coverage metadata as opaque legacy regions. Insert the new timestamp/original before those retained regions and rebuild exact fingerprints. Preserve verified generated HTML where available; otherwise render the verified plaintext with safe escaping. Never rebuild the tail through a model-output parser or invent a new coverage notice.

The current recovery model only carries generated text/HTML, while coverage text is a separate metadata region. Adjust that transient recovery representation to preserve the existing trailing metadata too. Keep original-entry identity and order checks. Do not guess boundaries from visible “AI Insights” text. If the full boundary is not trustworthy, protect the old note and use the normal independent-save fallback.

Title-only replacement already preserves non-title regions; retain that behavior. Keep legacy links and original extraction for read-only reviews. Old insights can remain visibly outdated; preserving user data is preferable to silently deleting it. Cleaning existing notes would require a separate request.

### 4. Remove only supplement UI and instructions

Remove Add Extra Ideas and its Writing Preferences link/editor, supplement-specific help, and the legacy rewrite notice. Remove inactive supplement preferences from active configuration and invalidation paths, but do not erase their stored values. Keep grouping, title help, review enable/scope, thinking-prompt settings and general background instructions. Remove unused localized strings without touching retained feature labels.

### 5. Reconcile contracts and Current docs at implementation

The current assistance spec requires generation, while presentation/grouping specs require refresh behavior. The deltas explicitly replace those contracts. At spec sync, update the existing assistance/presentation Purpose text to describe retired generation and compatibility; this planning turn leaves main specs unchanged. Update CONTEXT.md, Apple Notes integration, product/settings and AI docs where they currently promise saved insights. Preserve the independent title, review and thinking-prompt specs; remove obsolete supplement mentions there only if needed to keep wording coherent, without changing their behavior.

## Risks / Trade-offs

- Removing shared coordinator code could break title recovery or FIFO writes → retain those paths and check their call sites separately from deleted refresh code.
- Old generated text or coverage metadata could be lost on append → preserve complete verified tail regions and compare assembled plaintext/boundaries through isolated checks.
- A legacy uncertain refresh could be repeated or forgotten → retain decoding and read-only reconciliation, with no new refresh producer.
- Existing tests assert a removed feature → update or retire only those existing cases; do not add tests. Run retained original-save and model/provider checks without real Notes or network calls.
- Existing edits can change before apply → inspect the live diff again and make only scoped edits. Do not reset or stage unrelated work.
- Public Notes read-then-write is not atomic with external edits → keep the existing final full read and readback guards; do not claim this change removes that race.

## Migration Plan

1. Ship caller/UI removal together with legacy decoding and rendering compatibility. Keep stored settings and ledger data; perform no Notes cleanup on upgrade.
2. Verify ordinary save, grouped append, pending title and legacy readback with isolated existing checks. Confirm no supplement-generation caller or refresh-write producer remains.
3. Run `swift build` and affected existing tests. Real-window Notes display is a separate manual check; do not launch or drive the app by default.
4. Sync delta specs and Current docs only after implementation. Follow repository delivery rules only within the later apply request's scope.

Rollback restores the earlier application code against the retained preferences and ledgers; no reverse content migration is required. That earlier code may resume supplementation according to its old saved preference, so rollback is not a promise that the removed feature stays off.
