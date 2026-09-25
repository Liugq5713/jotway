# Jotway documentation

This page is the only documentation entry point. A document's role determines whether it is authoritative.

- **Current**: describes behavior that exists now.
- **Work**: a temporary proposal or implementation brief; it is not current behavior.
- **Reference**: reusable external, protocol, or operational facts.
- **Decision**: the durable reason behind a hard-to-reverse choice.

Terminology lives only in [CONTEXT.md](../CONTEXT.md). When a Current document and code disagree, reconcile them in the same change rather than adding another explanation.

## Current product

| Document | Scope |
|---|---|
| [Product overview](product/overview.md) | Positioning, main flow, and product boundaries |
| [First use](product/first-use.md) | Entry points, shortcut setup, and the first successful action |
| [Settings](product/settings.md) | Current settings navigation and persistence boundaries |
| [Architecture](development/architecture.md) | Runtime modules and the routing/execution flow |
| [Data model](development/data-model.md) | Launcher datasets and independent database initialization |
| [Environment](development/environment.md) | Build, package, application identity, and storage |
| [Runtime logs](development/runtime-logs-research.md) | Privacy boundary, retention, export, and clearing |
| [AI capability](plugins/ai.md) | Optional text processing and configuration |
| [Plugin distribution](plugins/README.md) | Source and package boundaries for optional capability |
| [App updates](product/updates.md) | Sparkle configuration and user-visible update behavior |
| [Website and usage images](development/website.md) | English static site, interactive demo, verified download metadata, and README captures |

## Current actions and routing

| Document | Scope |
|---|---|
| [Apple Notes](integrations/apple-notes.md) | Default action, destination, and text writing |
| [Apple Reminders](integrations/apple-reminders.md) | Reminder routing, due date, and destination |
| [Apple Calendar](integrations/apple-calendar.md) | Calendar routing, time range, and destination |
| [Chrome](integrations/chrome.md) | Google search in Chrome |
| [ChatGPT](integrations/chatgpt.md) | Desktop conversation with prefilled text and manual send |
| [Jev intent recognition](integrations/jev-intent-research.md) | Model suggestion, local priority, switching, and feedback |

## Work documents

These describe active or candidate changes. Their contents do not override Current documents.

| Document | State |
|---|---|
| [Launcher UI](development/launcher-ui.md) | Active design brief |
| [Editor cursor alignment](development/editor-cursor-alignment.md) | Confirmed follow-up: integrate, verify, and deliver the existing caret alignment fix |

Delete a Work document after its resulting behavior has been merged into the relevant Current document.

## Decisions and references

| Document | Role |
|---|---|
| [Launcher pivot](development/launcher-refactor.md) | Decision: transient launcher instead of local inbox |
| [Connector to action](development/launcher-connector-to-action.md) | Decision: one action abstraction |
| [Jev API](integrations/jev-api-research.md) | Reference: external protocol and uncertainty boundary |
| [AI provider onboarding](development/ai-provider-onboarding.md) | Reference: adding an AI source |
| [AI provider implementation](plugins/ai-provider-implementation.md) | Reference: provider request path |
| [Third-party notices](../THIRD_PARTY_NOTICES.md) | Reference: dependency sources and licenses |

## Maintenance rules

1. Write the smallest Work brief that makes a change testable: scenario, current behavior, target behavior, non-goals, and acceptance criteria.
2. Keep Current docs timeless. Do not append delivery dates, build durations, PIDs, local installation receipts, or chronological implementation logs.
3. After implementation, update one Current document and delete the completed Work brief. Git is the archive.
4. Keep research only when its sources or uncertainty boundaries will be reused.
5. Create a decision record only when the choice is hard to reverse, surprising without context, and the result of a real trade-off.
