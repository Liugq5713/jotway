# Architecture

> Role: **Current**

Jotway has a main SwiftPM executable and a separately sandboxed OCR helper. SwiftUI owns application and settings surfaces; AppKit owns the non-activating quick panel and focus-sensitive input flow. The source directories remain the main application’s architectural boundary. Its UI and core are not split into separate SwiftPM targets because they still share main-actor dependencies, and splitting them would add cycles or broad `public` APIs.

## Startup and runtime boundary

`JotwayBootstrap` is the process entry point. It runs `StorageMigration` before constructing the SwiftUI App, property wrappers, AppState, stores, credentials, hotkeys or collection. `StorageLocation` uses the account home rather than sandbox-redirection APIs. Migration stages and validates a source-preserving copy, journals promotion and preference adoption, and only then enters normal startup. An interrupted or conflicting migration stays in a minimal recovery surface; it cannot take the ordinary database fallback path. See [Direct distribution runtime](../../openspec/specs/direct-distribution-runtime/spec.md) and [storage recovery](environment.md#storage-recovery).

The main executable is not sandboxed; it retains Apple Events entitlement and Hardened Runtime. OCR is separately signed with its own sandbox and embedded helper identity. Its only payload channel is bounded stdin/stdout; the parent drains output while writing input and retains process ownership until exit. Public distribution adds Developer ID, timestamp, notarization, staple and Gatekeeper checks; local development packaging does not claim those checks.

## Runtime modules

- `App`: the composition root plus focused modules for action configuration, shortcut trials, onboarding, application usage, and Sparkle updates.
- `Actions`: the action descriptor/contract, registry, text processing, executor, and bundled actions.
- `Features/Editor`: native multi-line plain-text editing and the SwiftUI adapter. Markdown-like syntax remains literal, and paste or drop paths cannot introduce attachments or rich-text styling.
- `Features/Launcher`: installed-application matching, intent recognition, the pure route resolver, and the in-memory launcher session.
- `Window`: panel lifecycle, native focus, and interpretation of launcher effects.
- `Data`: migrations and `LauncherStore`, which persists only launcher-support data.
- `Integrations` and `Support`: optional AI, Chrome source capture, Apple Notes, key storage, logs, and platform helpers.

## One-way launcher flow

The UI reads `LauncherViewState` and sends every user intent as a `LauncherEvent`. `LauncherSession.send(_:)` is the sole business-state entry point. Native editor details remain in `EditorFocusTarget`; it is not a callback bus.

`LauncherSession` emits `LauncherEffect` values for editor replacement, submission presentation, panel visibility, action setup, and application opening. `PanelController` interprets those effects and does not choose routes or execute actions itself.

## Routing

`RouteResolver` is a pure value-type module and the only implementation of destination priority:

1. The user's explicit target selection.
2. A bundled action keyword match.
3. A current recognition suggestion that is still available.
4. The ready action with the lowest declared fallback priority; registration order breaks ties. Notes is the only bundled storage fallback.
5. A module-provided setup fallback when no storage action can execute; only Notes declares a fallback priority. Codex also provides setup for explicit target selection.
6. An explicit unavailable reason if a custom registry has neither an executable fallback nor a setup entry.

An execution or `.setup(actionID, source)` `RouteDecision` carries its source (`explicit`, keyword, recognition, or fallback). Display, preparation, confirmation, and operation recording consume that same value instead of re-deriving why a route won. Setup is available to explicit selection, local keywords, and fallback, but never enters execution preparation or application candidates. An explicitly selected target remains selected by stable ID across suggestion and configuration updates; if it becomes unavailable, confirmation reports that condition instead of silently falling back. Application launch is a local route, never a default action: ordinary draft input can match a direct application name or `打开 应用名`, while leading `/` and `、` stay in the draft and do not activate a separate command menu.

Legacy `@notes`, `@personal`, `@codex` and `@clipboard` names are literal input, including when explicitly sent to the same action. No prefix selects a target, starts setup, locks the target menu or hides its capsule. Ordinary bundled keywords and local application matching retain their existing eligibility.

`InputTemplate` defines two immutable built-ins and custom stable IDs, names and bodies. `AppState` injects `TemplateConfiguration`, which validates and stores a versioned local definition list. `TemplateExpansion` is a pure parser producing plain text, UTF-16 field ranges, a final position and source error positions. The native `EditorTextView` alone owns `TemplateEditingSession` and selected ranges; launcher state exposes only whether filling is active.

In quick input, a single-line leading `@` query filters template names. `EditorFocusTarget` owns the picker highlight. The identity-bound `insertTemplate` effect is accepted by `PanelController` only for the current editable draft and non-composing editor. A single native replacement suppresses its binding echo until the session accepts one text update; it retains the draft and explicit target. Undo restores the query and selection; Redo restores text without field anchors. Filling follows safe edits, visits numbered fields with Tab/Shift+Tab and ends on Esc, unsafe selection/edit, Undo/Redo, accepted submission, hide, replacement or mode change. IME remains first. The picker temporarily covers the existing target-specific area, blocks execution and dismisses until text changes. No template choice sends, copies, reads Notes or starts setup. Historical `remove_action_mention` operation values remain decodable, but new submissions never emit that transform.

Each in-memory draft has a routing mode keyed by `draft.id`. Explicit mode holds a stable target ID and display-name fallback, independently of `ActionInput.Identity.revision`. Editing, composition intermediates, quoting, hiding, and reopening keep that mode while invalidating obsolete recognition and preparation. A meaningful-to-empty completed edit ends the selection; a nonempty atomic replacement does not. Accepted submission and Use Automatic also end it. Neither a blocked confirmation nor an editor refusing replacement may clear the choice.

`LauncherViewState` separately exposes whether the target menu can open, another target can be cycled to, a choice is explicit, and a nonempty draft can be confirmed. Action and setup candidates do not require a nonempty recognition snapshot; local application candidates still do. `RouteResolver` retains its empty-text execution guard and automatic priority order. Use Automatic is a session event, not an action or cycling candidate, and immediately resolves available local information without waiting for the network.

A separate routing-operation revision protects empty drafts from stale failures. Submission snapshots retain the original mode. Automatic failure recovery restores text and mode atomically only when neither text nor routing activity has changed; explicit recovery into an untouched empty draft restores both, while a merge keeps the current mode. Application dispatch clears selection only when accepted, and a failed dispatch completion can restore it only while its text and routing revision are still current. Setup cancellation retains the original selection; successful setup selects its action and still needs a later confirmation.

## Action boundary and execution

`ActionModule` is a long-lived main-actor object that owns one stable descriptor, typed configuration, availability state, dynamic settings summary, an optional settings-view factory, and an optional setup entry that defaults to absent. `ActionDescriptor` declares identity, execution and settings labels, icon and tint, settings group, enablement policy, fallback priority, local keywords, and presentation policy. `BundledActions` is the only concrete built-in list.

`ActionRegistry` owns modules in registration order and aggregates settings entries, availability, a registry revision, ready-only `ActionExecutionSnapshot` values, and separate configurable candidates. Retired custom phrase preferences remain untouched and are not loaded into routing; disabled or temporarily unavailable registered modules remain visible and configured. `ActionConfiguration` owns only common enablement preferences. Module-specific destinations, content-assistance options, and preference adapters stay inside their modules.

External availability is module-owned display state. Input, composition and configuration refresh consume it without application scans. Availability refresh has separate registration, presentation, settings and workspace triggers. Generation and module-instance guards reject obsolete results. Only an actual availability change publishes a registry update. Confirmation still rechecks the displayed target before an external effect.

Confirmation still calls the synchronous availability recheck. Before it does, the session captures the rendered route and input identity. A changed destination or action/setup kind blocks the confirmation and preserves the draft. External actions independently locate and validate their destination again when executing; a stale display cache never authorizes an external effect. Probe completion can refresh state but cannot show a hidden panel.

`LauncherAction` is a Sendable, short-lived execution value frozen from current module configuration. Synchronous preparation returns an `ActionPlan` or throws a safe failure. The plan freezes action ID and input identity; its asynchronous build returns a `PreparedAction` with the same plan identity. No schedule resolver, time summary or presentation acknowledgement participates in this boundary.

`ActionExecutor` owns plans, body prewarming, cancellation, and cache identity: action ID, draft identity, module instance, module configuration revision, registry revision and session generation. It publishes preparation results rather than discarding failures. Cancelled or obsolete work cannot refill the cache or replace a newer result. Descriptors default to preparation before confirmation. Notes opts into preparation after confirmation: the executor publishes a ready deferred action that freezes the plan and runs its build only in the accepted execution task.

`LauncherSession.confirm` gates Enter, Command+Enter and target-capsule pointer confirmation. A transparent native mouse region rejects marked text before focus can leave the editor and forwards one `.confirm(.button)` through `PanelController`; it shares guards with the named accessibility action. Keyboard menu entry uses `canChooseTarget`, while pointer confirmation uses `canConfirm` and also rejects review/protected states. Clicking an open target menu’s capsule only closes it and restores editor focus; selecting a candidate or automatic routing still does not submit. See [Launcher appearance](../../openspec/specs/launcher-appearance/spec.md). One confirmation may wait for preparation, while duplicate confirms cannot multiply writes. Input, target or configuration changes, focus loss, dismissal and composition cancel unaccepted confirmations. Local matches cannot reroute a waiting confirmation.

Blocking preparation or availability failures preserve text and selection, record only `confirmationBlocked`, and create no Attempt. The correction target stays fixed while that draft is edited. Every adoption checks current action, draft, configuration, registry and panel-session identity.

For external actions, after readiness and final identity checks, the session creates an Attempt, clears the draft, animates, hides, and transfers ownership to the execution task. Notes is ready with a deferred body build, so history retrieval and supplementation cannot delay that handoff. Settings changes, a new draft, or panel dismissal after that handoff do not reconfigure the submitted request.

`PanelController` hosts one module-provided setup window and restores the editor through the session. Setup retains text, selection, and draft identity and pauses recognition. Session tokens and draft identity reject repeated or stale callbacks; successful setup selects the configured action only for the original draft and requires a new confirmation to execute. Cancellation returns without submitting. Setup neither clears the draft nor creates an execution attempt. Its own start/finish events distinguish completed, cancelled, and failed configuration.

Notes owns permission and destination selection and maps Apple Events errors. Explicit authorization uses Authorize or Authorize Again; opening settings, typing and prewarming never request permission. Authorized reads retain valid saved folders, otherwise use the default account’s default folder, another default folder, then the first exposed folder. Settings offers Change…; launcher setup authorizes without a picker. Setup neither writes test content nor requires verification.

A known authorization or destination failure retains the saved destination, invalidates executable availability, and exposes a System Settings link plus Authorize Again. Successful authorization and destination resolution clear the failure. Notes continues to expose the generic launcher setup entry, for Notes authorization.

Actions translate service-specific failures into `ActionFailure`, which is the only user-displayable execution error boundary and carries a safe message, bounded diagnostic code, optional numeric `osStatus`, and an explicit failed/unknown effect. `ActionOutcome` carries a structured effect; the recorder never infers success from display text. The launcher does not inspect Apple-specific errors or expose unknown system descriptions.

External bundled actions opt into immediate feedback through `ActionOutcome.showsCompletionNotice` after their success checks pass. Notes returns `.created` only with a confirmed destination identifier; Codex returns `.completed` only after its CLI completion checks pass. `LauncherSession` records the result and emits `showCompletionNotice` with the submitted descriptor's optional `applicationBundleIdentifier` instead of storing a success message for the next panel opening. `PanelController` owns one `CompletionNoticePanel`, a non-activating panel that cannot become key or main. Its four-second dismissal task is replaced on new results and paused while hovered.

The notice body has an app-opening button only when the action declares a destination application. Its hosting view accepts the first click without activating Jotway. The click dismisses that notice and uses the controller's existing application-opening adapter with activation enabled; it re-resolves the application by bundle identifier at click time. The close button and timeout only dismiss. No execution callback or editor mutation is available from the notice. Missing applications and open failures produce a separate warning notice without changing the successful action result; a notice identity rejects stale clicks and errors after a newer result arrives. Thrown action failures continue through draft recovery without a success notice. The broader grouped submission-receipt work remains separate.

User-visible app copy is resolved from stable semantic localization keys at the display boundary. Descriptors, action outcomes, safe failures, and dynamic state retain keys, parameters, or stable IDs rather than translated strings whenever the value can outlive one render. English is the only shipped UI language; the resource boundary exists so another `.lproj` can be added later without making routing, persistence, or cached preparation language-dependent.

`LauncherSession` owns candidate ordering and explicit selection. `IntentRecognition` synchronously adopts local application evidence from the current snapshot and rejects stale input or unavailable targets. It has no model binding, request, debounce, cooldown or model-error state. `ApplicationMatcher.maximumTextBytes` retains the 12,000-byte guard. Ordinary text falls through to Notes without waiting.

For external actions the panel clears and hides optimistically after it has created the execution task. On failure, the submitted draft and routing mode are restored only if no newer edit or routing operation exists. Otherwise `FailedSubmission` retains the old text and mode without overwriting the new draft and can restore or merge it explicitly.

## Editor geometry and input work

`ActionPlanResultRow` uses the fixed 22 pt action row for safe preparation failures. Empty content keeps the same geometry. The row does not render a schedule or acknowledge plan presentation. Input and lifecycle changes clear stale failure and accessibility content without changing the row budget.

Native `EditorTextView` reports composition events only when its marked-text state changes. Ordinary insertion therefore does not run an additional composition-completion refresh or enqueue its reconciliation callback. Actual composition completion retains the native adapter's deferred synchronization. Height measurement still uses TextKit document layout and the existing last-line ink bounds; no layout-range approximation or delayed text write is used. `InputPerformance` supplies opt-in, content-free synchronous timing callbacks for isolated profiling and is inactive by default.

`LauncherSession.updateInput` materializes incoming bridged text once into contiguous UTF-8 storage before the draft, operation state, and observable view state compare or retain it. This changes string storage only: the original text, revision rules, composition handling, and synchronous refresh order stay the same.

## Application composition

`ApplicationCatalog` preloads at startup and refreshes in the background when the quick record panel is presented, at most once every 30 seconds after the last successful snapshot. Input events do not start scans. File enumeration, bundle reads, and search-term preparation run off the main actor; the previous snapshot stays searchable until its replacement is published. Requests during a scan are coalesced, cancellation permits a retry after the old worker exits, and obsolete results cannot replace a newer snapshot. Catalog notifications reuse the session's composition and explicit-selection guards without replacing editor text or submitting a draft. The scan locations are unchanged; publishing a catalog increments its revision and invalidates cached matching evidence.

Application search profiles include display names, filenames, localized names and valid string entries from `CFBundleAlternateNames`. Profiles prepare normalized text, word/camel-case boundaries, real-name words, Chinese pinyin and initials during catalog loading. Derived phonetic terms retain their origin separately from real names. Stable launcher identities are also prepared with the catalog; neither profile generation nor bundle reads belong on the keystroke path.

`ApplicationMatcher` is the pure local source of query classification, match quality and single-result selection. Its order is exact name, full-name prefix, word prefix, substring, scored ordered abbreviation, then a single-edit typo fallback. Broader matching accepts one alphanumeric query of 2–32 characters; exact names and existing multiword prefixes still work. Typo recovery accepts 4–32 ASCII letters, requires the same first letter and compares real-name words or their prefixes using one insertion, deletion, substitution or adjacent swap. It runs only when no eligible non-typo match exists and never corrects generated pinyin or initials. Ordinary sentences are not concatenated into fuzzy queries. An explicit launch command can use its first line as a query while preserving following content.

Matching quality precedes usage. Open count and recency resolve only equal-quality ties. Remaining ties use normalized display-name order and then stable application identity, so eligible matches always produce one recommendation without a network request. The display-name sort key is prepared with the profile; it does not depend on which alias matched. Duplicate identities keep their strongest evidence, with display-name order resolving equal evidence. Selection considers the full catalog, deduplicated by stable identity, before capping diagnostic matches at 32. `LauncherSession` caches an evaluation per draft and catalog revision; `IntentRecognition.Snapshot` carries that evidence into synchronous recognition and confirmation. Success invalidates the cache after updating usage. No per-keystroke bundle reads, path canonicalization, hashing or profile construction occur.

The target menu and Option+Up/Down expose at most one application alongside existing actions and setup entries. A pinned application occupies that slot and stays available by catalog identity through query edits; an actually missing target remains visibly selected but cannot execute. Explicit actions and local keywords keep their existing precedence. Successful launch clears text only when the submitted evaluation identifies that same application as the selected pure-launch winner and draft/session ownership still matches. Failed launches, intervening edits and command-adjacent content retain their text. Composition and menu-confirmation guards remain in the session and native adapter.

Application matching diagnostics retain `exact` and `prefix`, add `wordPrefix`, `substring`, `abbreviation` and `typo`, and decode future values as `unknown`. They reuse bounded operation metadata and exports without adding query-learning storage, database tables, raw-query logs or application paths to runtime diagnostics.


`AppState` connects the common module list, registry, and top-level services but does not expose concrete action destinations or service-call forwarding properties. `ActionConfiguration`, `ShortcutTrial`, `UpdateManager`, `OnboardingState`, and `ApplicationUsageStore` each contain their own state transitions and persistence seams. `JotwayApp` creates the store and app state, then constructs launcher sessions from those dependencies. Onboarding receives one registry-aggregated “saved action configuration exists” signal, so loading default modules does not make a fresh install look previously configured.

## Optional AI

The main process sends bounded requests directly to the registered DeepSeek or Moonshot HTTPS endpoint. Local plugin source may add compile-time hooks without changing that transport boundary. `ActionInput` carries both the existing trimmed body and the complete frozen original editor text. Actions declare whether they preserve original text, and operation confirmations record the corresponding input transformation. Notes consumes the complete original; other bundled actions retain their existing contract.

Notes has a separate supplement result containing bounded items and evidence-backed history associations. It never accepts a model-generated replacement body or title. The application assembles original text, an optional labeled supplement followed by related history before one Notes create request. The original-to-HTML conversion preserves whitespace and literal text syntax. Notes keeps its old AI enable preference, uses a separate supplement-preference key and leaves legacy rewrite styles inactive. Its accepted execution task bounds the entire optional history/provider pipeline to five minutes. A single completion gate returns on timeout without joining an unresponsive worker, cancels optional work, and ignores late results. Optional failure, service cancellation, or index invalidation falls back to original text without automatic tags; actual submission cancellation still prevents a write. Destination changes remain checked before writing.

## Persistence

The product persists application usage, local operation records, preferences, secrets, and runtime logs. `OperationRecorder` owns typed facts, immutable inputs and routing snapshots, a bounded background writer, capture-generation invalidation, retention, integrity, and manual exports. Session and recognition supply observations; the pure resolver never reads or writes records. Stable unsubmitted text is also captured when enabled. Editable drafts and failed-submission state remain memory-only and are never restored from records. See [Data model](data-model.md).

## Recent-copy browser attribution

AppState owns one ClipboardService and BrowserSourceSettings. PanelController delegates changeCount observation and one-use recent quotes to that service; isolated callers may inject a separate pasteboard. With history disabled, the 0.3-second observer reads no clipboard payload. Explicitly enabled Chrome Source may read the front Chrome tab through a PID-targeted adapter, with a shared 500 ms Apple Event budget and before/after identity checks. It keeps only the current in-memory candidate and one in-flight read. New copies, external application changes, disabled access and expiry invalidate attribution; restore versions are excluded.

The external global-hotkey path freezes source process identity and a recent-copy claim before focus changes. A dedicated single-flight AX worker reads only the focused element and its selection, with object messaging timeouts and an independent deadline. Selection and browser attribution share one 150 ms opening budget; valid or deduplicated selections consume the copy claim. Other entry points retain their existing clipboard behavior. See [Selected text capture](../../openspec/specs/selected-text-capture/spec.md).

Draft restoration precedes a successful native quotation insertion, whose receipt alone records per-draft adoption. Text, observable control/range identity and process identity stay in memory. Native undo restores text and the original selection without discarding earlier undo history.

Real presentation claims a quote using the invocation time. Draft and presentation identities, composition and setup state gate adoption. A claim has one adoption opportunity; cancellation and late results cannot rewrite a displayed draft. The source becomes ordinary editable text with no hidden submission payload.

## Local Clipboard path

AppState owns one `ClipboardService` shared with PanelController. A 300 ms change-count observer supplies recent text quotes, optional Chrome source attribution and enabled history capture. Disabled history never reads clipboard payloads in the background. Starting or enabling collection establishes a baseline, so old copies are not imported. History restore registers its own exact pasteboard version; that observation is excluded from history, OCR and recent quotes. A later external copy of identical bytes remains eligible.

`ClipboardHistory` serializes lifecycle changes and admits one bounded capture conversion at a time. Its actor store does image preview and SQL work off the main actor. OCR starts only after two seconds of keyboard/mouse idle time and uses one disposable `JotwayClipboardOCR` process at a time. Cancellation retains the worker slot until process exit. Generation, item ID, digest and OCR version reject late results. Closing a list releases its query projection and thumbnails; enabled background collection continues.

LauncherSession intercepts Clipboard input before ordinary recognition and action preparation. Its special local confirmation freezes the item, draft revision, panel session and history generation; only successful pasteboard writing clears input and emits the hide effect. The frozen ActionInput and operation events contain the query, never the restored payload or OCR. ClipboardHistoryView is mutually exclusive with the Codex lower card. Clipboard copy adds the `completed` local execution effect without an external submission.

The Clipboard keys have English and Simplified Chinese resources. AppLocalization continues to select English for the application; this change does not add a global language selector.
