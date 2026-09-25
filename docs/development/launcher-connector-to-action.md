# Decision: one action abstraction

> Role: **Decision**
> Decision: every executable destination implements `LauncherAction`; Connector is not a product or public code concept.

## Context

The previous design treated “send somewhere” and “save somewhere” as different species. This duplicated selection, availability, error handling, persistence, and settings behavior while the user experienced both as destinations for the same draft.

## Decision

Every executable destination is an action. Chrome uses the same registration, intent, selection, and execution path as Apple services.

Actions that must not receive unclassified drafts declare no `fallbackPriority`. Chrome remains reachable through explicit selection, local intent hints, or a valid Jev suggestion, but cannot silently become the fallback.

## Persistence trade-off

Chrome succeeds when macOS accepts the open request. A synchronous failure restores the draft.

## Consequences

- `Connector`, connector modes, and `@` target selection are retired terminology.
- Settings derives all destinations from the action registry.
- The database stores launcher support data without destination-specific submission tables.
- External task progress is not a Jotway state.
