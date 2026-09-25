# Decision: transient launcher instead of inbox

> Role: **Decision**
> Decision: Jotway routes a transient draft to one action and does not keep a local inbox.

## Context

The original product stored notes, displayed cards, generated Summary output, and tracked completion/export state. Rapid iteration made every new destination depend on that sediment layer even when the user's real goal was simply to send, save, search, or schedule a sentence.

## Decision

Jotway is a launcher. Draft text lives in memory, Enter executes exactly one action, and successful execution clears the draft. There is no second “save locally” outcome.

Apple Notes is the factory default action because it is a reversible, user-visible destination. Send/search actions cannot become an implicit fallback.

## Consequences

- Inbox, record history, cards, Summary, completion, export, and persistent destination-specific submissions are outside the product.
- A fresh database starts with the launcher schema; prior inbox data is outside this product.
- Destination-specific behavior moves behind one action boundary.
- External systems own their created content and completion state.
- Failure recovery restores the transient draft; Jotway does not create an internal recovery record.

## 2A. Current action architecture

### 2A.2 `LauncherAction`

An action owns a descriptor (identity, title, icon, intent hints, default eligibility, and presentation policy), runtime availability, preparation, and execution. Routing consumes descriptors; Settings currently uses explicit Apple destination cards.

### 2A.3 `ActionRegistry`

The registry owns registration and configuration. It provides enabled actions to intent recognition and stable-ID lookup to execution; `RouteResolver` alone interprets explicit selection, user rules, local keywords, recognition, and the default action.

## 2.4 Default action

Apple Notes is the preferred default. When unavailable, the registry selects the first available action allowed to act as a default. Chrome is excluded. A user-selectable default is not currently exposed.

## 2.6 Text pipeline

Storage actions may process text before writing. `ActionExecutor` prepares an action once per draft identity and action ID, then reuses that exact preparation for execution. Optional AI failure must not prevent the original text from reaching a usable destination.
