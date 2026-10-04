# Data model

> Role: **Current**

Jotway keeps application usage and local operation records in its SQLite database. Operation records include unsubmitted text when capture is enabled; they do not form an inbox or restore editable drafts after restart.

## Local operation records

`OperationRecorder` owns one normalized record of input, routing, selection, and execution:

| Table | Stored facts |
|---|---|
| `operation_inputs` | One complete, untrimmed text per lineage and input version, including whitespace and newlines |
| `operation_contexts` | Immutable, canonical routing configuration snapshots, reused by content digest and full comparison |
| `operation_attempts` | One confirmation's target, source, selection origin, confirmation entry, presentation references, and retry relation |
| `operation_events` | Append-only observations in database sequence order; results live here, with references to the input and context |

A lineage belongs to one draft and its failure recovery chain. Hiding or reopening preserves it. Restoring a failed attempt into an empty editor preserves its input identity; merging into a newer draft keeps the newer lineage and records the source. Input versions advance only when text changes, independently of editor/session revisions. Consecutive typing is sampled together, while recognition, selection, confirmation, hiding, and explicit clearing force a stable-text capture. Marked text from input-method composition is excluded. No 4,096-byte truncation is applied to stored text.

Contexts contain ordered Local Rules, action routing hints, safe availability reasons, fallback targets, recognition questions and thresholds, and app/rule/model identifiers. They exclude keys, accounts, destination content, and full service responses. Dynamic application candidates and validated model observations belong to the request events.

Visible routing is recorded only after the final decision reaches a visible, unobscured panel. Model results and the route actually presented are separate observations. A genuine choice, including one made on an empty draft, records `target_selected` and can reference the preceding presentation. Automatic selection after setup has a distinct origin. Neither hiding nor an unsubmitted input is a negative label.

An explicit target belongs to the runtime draft and can outlive an input version. Editing or reopening does not manufacture another selection event. A confirmation preserves its `user_choice` or `setup_completion` origin and records `selectionContinuity` as `direct` or `inherited`. A direct first-choice reference must name the first genuine user choice on the same input after the latest `Use Automatic` mode change. Inherited confirmations have no cross-input first-choice reference. When prior selection observations exist in the lineage, inheritance must agree with their latest target and origin; a recorded return to automatic ends that inheritance.

`Use Automatic` is a `target_selected` mode-change observation with `mode=automatic`, automatic origin, and no target or route-source value. It is not a registered action or a submission. Selecting A, returning to automatic, and then selecting B on the same input anchors the new explicit selection to B. Acceptance alone is not a user mode-change event. Earlier records without a mode field retain their explicit-selection meaning; earlier confirmations without continuity retain their direct meaning.

A confirmation transaction creates the attempt and `confirm_requested` together. `submission_accepted` means the execution task was acquired after availability and editor-clear checks, or an application-open request was actually dispatched. External results distinguish `created`, `opened`, `prefilled`, `accepted`, `failed`, and `unknown`. ChatGPT prefill does not prove a message was sent. Missing terminal observations remain unknown, including after crashes. Event-type, reference, ordering, and idempotency checks supplement SQL constraints.

## Retention, integrity, and export

Intent Recognition settings provides one capture toggle, storage and integrity status, retention days (default 90), export, and clear. Disabling capture deletes these records; clearing or disabling invalidates older callbacks before deleting. Local Rules, application usage, and RuntimeLog are independent and remain intact. Collection controls do not change the runtime draft's selected target. After collection is cleared or re-enabled, an existing runtime selection may be recorded as inherited with an unknown earlier anchor; it does not recreate deleted inputs or fabricate a click.

Retention removes whole lineages by their latest activity, defers in-flight executions, and prunes unused contexts. Late callbacks cannot recreate deleted inputs. A bounded serial queue performs disk work away from the main runtime path. Queue overflow, storage failure, and incomplete exit drains are reported as gaps, not silently treated as complete records.

A bounded atomic state file beside the database contains only capture generation, run ID, clean-drain state, and the first gap time and fixed reason. It never stores text or a second copy of events. An unfinished previous run or an unreadable/unwritable state file makes completeness unknown; known gaps remain until explicit clear. This does not promise immunity from power-loss failures.

Export reads one consistent database snapshot. JSONL carries schema, capture scope, generation, and integrity metadata, then each input/context/attempt once and events in sequence order. `attempts.csv` joins original text, preceding presentation, final choice, selection origin and continuity, confirmation, acceptance, result, timing, model/rule metadata, and retry identity, with empty annotation columns. Inherited attempts leave the first-choice and preceding-presentation fields empty when no same-input anchor exists; JSONL retains genuine selection and automatic-mode events. `unsubmitted.csv` marks `no_confirmed_attempt`; `legacy.csv` marks `legacy_partial`. Formula-leading CSV values are escaped as text; JSONL preserves originals. Action input trimming is identified explicitly rather than rewriting stored text.

## Application usage and other persistence

`application_usage` stores application path, open count, and last-opened time for local application ranking. Record deletion and migration do not change it.

The editable draft, selected target, prepared action, and failed submission remain memory-only and are cleared on process exit. Saved operation inputs are never used to restore them.

- `UserDefaults`: ordinary preferences, selected destinations, action enablement, manually maintained Local Rules, rewrite instructions, Notes tags, and record-management preferences.
- Restricted local files: AI and Jev API keys.
- JSONL files: bounded, content-free RuntimeLog diagnostics, independently managed.

## Migration

`v1_launcher` remains unchanged. A subsequent transactional migration creates the four operation tables, converts every old `intent_feedback` and `intent_corrections` row into a deterministic independent legacy lineage/input/event, verifies counts, IDs, text, reconstructed original JSON values, and foreign keys, then removes both old tables. Generic JSON decoding preserves unknown fields and enum values. Migrated text and determinable final target move into normalized columns; remaining original values are retained as versioned legacy details.

Legacy observations never manufacture attempts, presentation history, retries, acceptance, or execution duration. Their context is `legacy_partial`; missing facts stay absent. Any malformed row rolls back the entire migration, retaining the old tables. Reopening does not duplicate migration, and migration itself never expires history.

Jotway uses its own `Jotway/jotway.sqlite` location and does not import another application's data or credentials.
