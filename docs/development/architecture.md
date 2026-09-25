# Architecture

> Role: **Current**

Jotway is a single SwiftPM executable. SwiftUI owns application and settings surfaces; AppKit owns the non-activating quick panel and focus-sensitive input flow. The source directories are the architectural boundary; separate SwiftPM targets are not used because the current UI/core types still share main-actor dependencies and target splitting would add cycles or broad `public` APIs.

## Runtime modules

- `App`: the composition root plus focused modules for action configuration, shortcut trials, onboarding, application usage, and Sparkle updates.
- `Actions`: the action descriptor/contract, registry, text processing, executor, and bundled actions.
- `Features/Editor`: native multi-line plain-text editing and the SwiftUI adapter. Markdown-like syntax remains literal, and paste or drop paths cannot introduce attachments or rich-text styling.
- `Features/Launcher`: installed-application matching, intent recognition, the pure route resolver, and the in-memory launcher session.
- `Window`: panel lifecycle, native focus, and interpretation of launcher effects.
- `Data`: migrations and `LauncherStore`, which persists only launcher-support data.
- `Integrations` and `Support`: Jev, optional AI, Chrome, Apple services, key storage, logs, and platform helpers.

## One-way launcher flow

The UI reads `LauncherViewState` and sends every user intent as a `LauncherEvent`. `LauncherSession.send(_:)` is the sole business-state entry point. Native editor details remain in `EditorFocusTarget`; it is not a callback bus.

`LauncherSession` emits `LauncherEffect` values for editor replacement, submission presentation, panel visibility, action setup, and application opening. `PanelController` interprets those effects and does not choose routes or execute actions itself.

## Routing

`RouteResolver` is a pure value-type module and the only implementation of destination priority:

1. The user's explicit selection.
2. A saved user phrase rule.
3. A bundled action keyword match.
4. A current recognition suggestion that is still available.
5. The ready action with the lowest declared fallback priority; registration order breaks ties. Bundled storage actions are ordered Notes, Reminders, then Calendar.
6. A module-provided setup fallback when no storage action can execute; Notes is the only bundled module that provides one.
7. An explicit unavailable reason if a custom registry has neither an executable fallback nor a setup entry.

An execution or `.setup(actionID, source)` `RouteDecision` carries its source (`explicit`, rule, keyword, recognition, or fallback). Display, preparation, confirmation, and feedback consume that same value instead of re-deriving why a route won. Setup is available to explicit selection, phrase rules, local keywords, and fallback, but never enters execution preparation or Jev execution candidates. An explicitly selected target remains selected by stable ID across suggestion and configuration updates; if it becomes unavailable, confirmation reports that condition instead of silently falling back. Application launch is a local route, never a default action: ordinary draft input can match a direct application name or `打开 应用名`, while leading `/` and `、` stay in the draft and do not activate a separate command menu.

## Action boundary and execution

`ActionModule` is a long-lived main-actor object that owns one stable descriptor, typed configuration, availability state, dynamic settings summary, an optional settings-view factory, and an optional setup entry that defaults to absent. `ActionDescriptor` declares identity, execution and settings labels, icon and tint, settings group, enablement policy, fallback priority, local keywords, optional model binding, and presentation policy. `BundledActions` is the only concrete built-in list.

`ActionRegistry` owns modules in registration order and aggregates settings entries, availability, a registry revision, ready-only `ActionExecutionSnapshot` values, and separate configurable candidates. Persisted rules are admitted only after the complete module list is registered and are discarded when their action ID is no longer registered; disabled or temporarily unavailable registered modules remain visible and configured. `ActionConfiguration` owns only common enablement preferences and phrase rules. Module-specific destinations, rewrite options, and preference adapters stay inside their modules.

`LauncherAction` remains the Sendable, short-lived execution value created from a module's current configuration. Preparation freezes processed input and an execution closure as a `PreparedAction`. `ActionExecutor` keys reusable preparation by action ID, draft identity, module-instance identity, module configuration revision, and registry revision. Cancelled prewarms cannot refill the cache. Once confirmation takes ownership of a preparation task, later settings changes, new prewarming, or panel dismissal do not cancel or reconfigure that submitted operation.

`PanelController` hosts one module-provided setup window and restores the editor through the session. Setup retains text, selection, and draft identity and pauses recognition. Session tokens and draft identity reject repeated or stale callbacks; successful setup selects the configured action only for the original draft and requires a new confirmation to execute. Cancellation returns without submitting. Setup neither clears the draft nor produces execution or model-adoption feedback.

Notes owns its permission state and folder picker, including Apple Events error mapping. Folder reads begin only after the user opens configuration or asks to read again. A known authorization failure retains the saved destination, invalidates executable availability, and exposes repair guidance; successful authorized reading clears that failure. The explicit verification operation writes fixed test content, never the draft.

Actions translate service-specific failures into `ActionFailure`, which is the only user-displayable execution error boundary and carries only a safe message plus bounded diagnostic code and optional numeric `osStatus`. The launcher does not inspect Apple-specific errors or expose unknown system descriptions.

User-visible app copy is resolved from stable semantic localization keys at the display boundary. Descriptors, action outcomes, safe failures, and dynamic state retain keys, parameters, or stable IDs rather than translated strings whenever the value can outlive one render. English is the only shipped UI language; the resource boundary exists so another `.lproj` can be added later without making routing, persistence, or cached preparation language-dependent.

`LauncherSession` owns candidate ordering and explicit selection. `IntentRecognition` owns only local application matching, model requests, suggestion lifetime, staleness checks, and diagnostics. Model participation is opt-in through `.capture(criteria:)` or `.webSearch`; `.none` is the default. Capture results are accepted only when the returned ID belonged to that request's capture options, and Google results are accepted only when that snapshot had an available web-search binding.

The panel clears and hides optimistically after it has created the execution task. On failure, the submitted draft is restored when no newer edit exists. If the user has already started a new draft, `FailedSubmission` retains the old text without overwriting the new draft and can restore it explicitly.

## Application composition

`AppState` connects the common module list, registry, and top-level services but does not expose concrete action destinations or service-call forwarding properties. `ActionConfiguration`, `ShortcutTrial`, `UpdateManager`, `OnboardingState`, and `ApplicationUsageStore` each contain their own state transitions and persistence seams. `JotwayApp` creates the store and app state, then constructs launcher sessions from those dependencies. Onboarding receives one registry-aggregated “saved action configuration exists” signal, so loading default modules does not make a fresh install look previously configured.

## Optional AI

The main process sends bounded requests directly to the registered DeepSeek or Moonshot HTTPS endpoint. Local plugin source may add compile-time hooks without changing that transport boundary. Action-specific text processing must fall back to the original text when it is disabled or unavailable.

## Persistence

The current product persists application usage, intent feedback/corrections, preferences, secrets, and runtime logs. The draft and failed submission are memory-only. There is no user-facing content record or runtime attachment storage, but intent feedback and corrections contain copies of confirmed draft text. See [Data model](data-model.md).
