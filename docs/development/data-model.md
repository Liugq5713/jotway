# Data model

> Role: **Current**

Jotway keeps a SQLite database for small launcher-support datasets. It is not a user-content inbox.

## Live tables

### `application_usage`

Stores an application path, open count, and last-opened time. Local application matching uses this to choose among otherwise valid candidates.

### `intent_feedback`

Stores an accepted routing sample and a separate execution observation. The sample includes the full draft text, chosen target, recognition source, model/rule identifiers, and confirmation source. Recognition and execution remain separate so a failed action does not rewrite what the model suggested.

Historical samples whose diagnostic enum value is no longer known remain readable as a fixed non-executable `unknown` state. The stored sample, target ID, and text are not rewritten, and the unknown value cannot register or route an action.

These rows currently have no retention limit and no user-facing clear control. They are local, but they are persisted content and must be included in privacy or deletion work.

### `intent_corrections`

Stores cases where the user changed Jev's proposed target before confirmation. Each row includes the full draft text plus proposed/chosen targets. Rows stay local, are visible and clearable in Settings, and are capped at the most recent 200 entries.

## Memory-only state

The unconfirmed draft, selected target, prepared action, and failed submission live in memory. Process exit clears them. Confirmation may copy the text into the feedback tables above; it never creates a browsable Jotway record.

## Other persistence

- `UserDefaults`: ordinary preferences, selected destinations, action enablement, user intent rules, rewrite instructions, and Notes tag options.
- Restricted local files: AI and Jev API keys.
- JSONL files: bounded runtime diagnostics.

## Database initialization

`Database.swift` registers `v1_launcher`, which directly creates the three launcher tables above and the correction ordering index. GRDB records the applied migration, so reopening or migrating the same database preserves existing Jotway data. Future schema changes append migrations to this chain.

Jotway uses its own `Jotway/jotway.sqlite` storage location. No predecessor database or retired inbox, attachment, or submission schema is imported.
