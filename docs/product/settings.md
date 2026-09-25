# Settings

> Role: **Current**

Settings are organized by the user's decision, not by implementation module.

## Navigation

- **General**: appearance, panel placement, submission effect, global shortcut, launch at login, Dock visibility, and runtime logs.
- **AI**: AI source, model, key, connection test, and provider-specific fields.
- **Intent Recognition**: Jev key, connection test, explanation, and recent local corrections.
- **Actions**: destination setup for Apple Notes, Reminders, and Calendar.
- **Instructions**: manual AI instructions and prompts when the AI capability is present.
- **Getting Started**: a repeatable version of onboarding.
- **About**: version, update controls, download link, and contact link.

The sidebar groups configuration separately from help. Every page has a title and short description above a scrollable, grouped form. The window opens at 820 × 640 points, supports resizing down to 760 × 560, and limits form width on larger windows. Controls and surfaces follow the selected light, dark, or system appearance.

General settings group appearance, quick record behavior, startup, and diagnostics. Runtime-log controls are available in a collapsed disclosure group. AI settings separate source/model, credentials, and connection testing. Instruction editors keep restore-default on the left and cancel/save on the right; changes still require an explicit save.

Jotway currently ships an English-only interface and does not expose a language setting or follow the macOS interface language. App-owned display copy, action labels, dynamic status, and safe errors are resolved from semantic keys in the English package resource. Stable IDs and machine state never store translated text. This resource boundary is the extension point for adding another language later without changing routing, persistence, or action configuration. User-authored text, destination names, and installed application names remain unchanged.

## Usage guide

Getting Started is a scrollable daily reference as well as a repeatable onboarding page. Its first section explains the complete input → target → confirmation flow and provides direct actions to open the quick record panel or configure Actions. The page shows the actual configured shortcut and conflict state, preserves shortcut editing and trial behavior, and links directly to Actions and Intent Recognition settings.

The guide covers the four bundled actions plus local application opening, current keyboard behavior, plain-text input limits, optional intent recognition, per-action AI rewriting, in-memory draft lifetime, failure behavior, and the distinction between content in target applications and local intent feedback. It never treats panel dismissal as success or promises a browsable local inbox. Opening or leaving the guide does not replace, submit, or clear the current draft.

## Action settings

The Actions page shows the bundled actions:

- Apple Notes requires a Notes destination and permission to execute and is the preferred fallback. It also supports an optional fixed text tag, AI-generated related tags, and an independent AI rewrite switch and style instruction.
- Apple Reminders requires a reminder list and has its own AI rewrite switch and style instruction. Disabling rewrite also disables natural-language due-date extraction, so the due date falls back to the current time.
- Apple Calendar requires a calendar and has its own AI rewrite switch and style instruction. Disabling rewrite also disables natural-language time extraction, so the event falls back to a one-hour range starting at the current time.
- Chrome exposes an enable switch. When disabled, it is removed from recognition, selection, and routing.

The Actions page is generated from the registry's settings entries, including disabled, unconfigured, and temporarily unavailable modules. Labels, icon and tint, grouping, dynamic summary, enablement policy, and fallback marker all come from module declarations and state. Storage actions appear as full-width, keyboard-accessible rows with their selected destinations. Selecting a row opens the module-provided detail page; navigation stores only the stable action ID, and the header's back button returns to the list. Chrome's enable switch is directly available in the search section. Long destination names wrap instead of being truncated.

Each storage module owns its typed destination picker, validation sheet, rewrite controls, and persistence adapter. The common settings host neither switches on concrete action IDs nor uses a generic configuration-field DSL. User-editable style text cannot replace the system-owned date and structured-output rules. A user-selectable default action is not implemented; the ready module with the lowest declared fallback priority wins, currently Notes, then Reminders, then Calendar. If no storage action is ready, the launcher offers Set Up Notes rather than executing another kind of action.

Notes uses the same folder configuration view from its settings detail and the launcher’s Set Up Notes entry. A user opens the configuration flow before its initial Apple Events folder read can request authorization; background typing and prewarming do not request permission. Verify and Finish is an explicit operation with a visible explanation that it creates a fixed test note. It never uses or submits the current draft. Completing or cancelling launcher setup returns to the original text and selection; a successful setup waits for another Enter to save.

Denied or revoked Notes authorization preserves the saved destination and offers another folder read plus a link to System Settings → Privacy & Security → Automation → Jotway → Notes. Permission errors retain their meaning instead of appearing as an empty folder list. The app does not reset system permissions or automatically retry an uncertain write.

After all bundled modules are registered, Jotway removes saved rules and `actionEnabled.*` keys whose action ID is no longer registered. A registered action keeps its preferences when the user disables it or its external destination is temporarily unavailable. Existing destination, rewrite, prompt, tag, enablement, and rule keys retain their previous encoding and meaning.

## Persistence and secrets

- Ordinary preferences, action enablement, rewrite instructions, Notes tag options, and selected destinations use `UserDefaults`.
- AI and Jev keys are stored in local per-user files with restricted permissions and are not echoed back in the UI.
- Intent corrections include the draft text, remain local, retain the most recent 200, and can be cleared from Intent Recognition settings.
- Accepted intent-feedback samples also include the full draft text. They remain local but currently have no retention limit or user-facing clear control.
- Changing a source, model, or prompt invalidates stale connection-test conclusions.

## Connection tests

Connection tests use fixed sample content. They do not send the current draft. A successful connection proves reachability and response shape, not production recognition quality.

## Runtime logs

General settings can open, export, or clear runtime logs. Export includes the current Jev rule definition so a diagnostic bundle remains interpretable. See [Runtime logs](../development/runtime-logs-research.md).
