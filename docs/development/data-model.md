# Data model

> Role: **Current**

Jotway keeps application usage and local operation records in its SQLite database. Operation records include unsubmitted text when capture is enabled; they do not form an inbox or restore editable drafts after restart.

All application-owned persistent stores share the account-home `Library/Application Support/Jotway` root. `StorageMigration` adopts the prior container state before stores or defaults are initialized, including SQLite transaction sidecars and persistent false/unknown preference values. A completed journal never reimports the older snapshot. Recovery and rollback boundaries are defined in [Direct distribution runtime](../../openspec/specs/direct-distribution-runtime/spec.md).

## Local operation records

`OperationRecorder` owns one normalized record of input, routing, selection, and execution:

| Table | Stored facts |
|---|---|
| `operation_inputs` | One complete, untrimmed text per lineage and input version, including whitespace and newlines |
| `operation_contexts` | Immutable, canonical routing configuration snapshots, reused by content digest and full comparison |
| `operation_attempts` | One confirmation's target, source, selection origin, confirmation entry, presentation references, and retry relation |
| `operation_events` | Append-only observations in database sequence order; results live here, with references to the input and context |

A lineage belongs to one draft and its failure recovery chain. Hiding or reopening preserves it. Restoring a failed attempt into an empty editor preserves its input identity; merging into a newer draft keeps the newer lineage and records the source. Input versions advance only when text changes, independently of editor/session revisions. Consecutive typing is sampled together, while recognition, selection, confirmation, hiding, and explicit clearing force a stable-text capture. Marked text from input-method composition is excluded. No 4,096-byte truncation is applied to stored text.

New contexts contain an empty legacy `localRules` field, action routing hints, safe availability reasons, fallback targets, recognition questions and thresholds, and app/rule/model identifiers. They exclude keys, accounts, destination content, and full service responses. Dynamic application candidates and validated model observations belong to the request events. Historical nonempty `localRules` snapshots and `user_rule` route sources retain their original decoding and export meaning, but never participate in new routing.

Visible routing is recorded only after the final decision reaches a visible, unobscured panel. Model results and the route actually presented are separate observations. A genuine choice, including one made on an empty draft, records `target_selected` and can reference the preceding presentation. Automatic selection after setup has a distinct origin. Neither hiding nor an unsubmitted input is a negative label.

An explicit target belongs to the runtime draft and can outlive an input version. Editing or reopening does not manufacture another selection event. A confirmation preserves its `user_choice` or `setup_completion` origin and records `selectionContinuity` as `direct` or `inherited`. A direct first-choice reference must name the first genuine user choice on the same input after the latest `Use Automatic` mode change. Inherited confirmations have no cross-input first-choice reference. When prior selection observations exist in the lineage, inheritance must agree with their latest target and origin; a recorded return to automatic ends that inheritance.

`Use Automatic` is a `target_selected` mode-change observation with `mode=automatic`, automatic origin, and no target or route-source value. It is not a registered action or a submission. Selecting A, returning to automatic, and then selecting B on the same input anchors the new explicit selection to B. Acceptance alone is not a user mode-change event. Earlier records without a mode field retain their explicit-selection meaning; earlier confirmations without continuity retain their direct meaning.

A confirmation transaction creates the attempt and `confirm_requested` together. `submission_accepted` means the execution task was acquired after availability and editor-clear checks, or an application-open request was actually dispatched. External results distinguish `created`, `opened`, `prefilled`, `accepted`, `failed`, and `unknown`. ChatGPT prefill does not prove a message was sent. Missing terminal observations remain unknown, including after crashes. Event-type, reference, ordering, and idempotency checks supplement SQL constraints.

## Retention, integrity, and export

App Suggestions settings provides one capture toggle, storage and integrity status, retention days (default 90), export, and clear. Disabling capture deletes these records; clearing or disabling invalidates older callbacks before deleting. Retired rule preferences, application usage, and RuntimeLog remain intact. Collection controls do not change the runtime draft's selected target. After collection is cleared or re-enabled, an existing runtime selection may be recorded as inherited with an unknown earlier anchor; it does not recreate deleted inputs or fabricate a click.

Retention removes whole lineages by their latest activity, defers in-flight executions, and prunes unused contexts. Late callbacks cannot recreate deleted inputs. A bounded serial queue performs disk work away from the main runtime path. Queue overflow, storage failure, and incomplete exit drains are reported as gaps, not silently treated as complete records.

A bounded atomic state file beside the database contains only capture generation, run ID, clean-drain state, and the first gap time and fixed reason. It never stores text or a second copy of events. An unfinished previous run or an unreadable/unwritable state file makes completeness unknown; known gaps remain until explicit clear. This does not promise immunity from power-loss failures.

Export reads one consistent database snapshot. JSONL carries schema, capture scope, generation, and integrity metadata, then each input/context/attempt once and events in sequence order. `attempts.csv` joins original text, preceding presentation, final choice, selection origin and continuity, confirmation, acceptance, result, timing, model/rule metadata, and retry identity, with empty annotation columns. Inherited attempts leave the first-choice and preceding-presentation fields empty when no same-input anchor exists; JSONL retains genuine selection and automatic-mode events. `unsubmitted.csv` marks `no_confirmed_attempt`; `legacy.csv` marks `legacy_partial`. Formula-leading CSV values are escaped as text; JSONL preserves originals. Action input trimming is identified explicitly rather than rewriting stored text. A confirmed leading `@` action records `remove_action_mention`; stored input still includes the marker, while the action consumes its extracted body under its own whitespace-preservation contract.

## Application usage and other persistence

`application_usage` stores application path, open count, and last-opened time for local application ranking. Record deletion and migration do not change it.

The editable draft, selected target, prepared action, and failed submission remain memory-only and are cleared on process exit. Saved operation inputs are never used to restore them.

- `UserDefaults`: ordinary preferences, selected destinations, action enablement, retained inactive legacy rule data, rewrite instructions, Notes tags, and record-management preferences.
- Restricted local files: AI and Jev API keys.
- JSONL files: bounded, content-free RuntimeLog diagnostics, independently managed.

## Recent saved Notes references

`RecentSavedDocuments` stores at most three unique `RecentSavedDocument` values in the separate `notes.recentSavedDocuments.v1` UserDefaults key. Each value contains only a Notes `id` and `savedAt` confirmation time. Confirmed successful Notes outcomes move that ID to the front, refreshing its time; daily grouped appends do not create duplicate document references. Other actions, failed or uncertain writes do not add entries. Loading the preference restores the saved references without scanning or backfilling Notes history.

This feature stores no title or body and adds no SQLite tables or migrations. Detail plaintext is read live from Notes after activation and held only for the current detail view. Closing it, hiding the panel or switching modes clears that state; stale read callbacks cannot restore it. These references are independent of editable drafts, operation-record retention and the derived Notes index.

## Migration

`v1_launcher` remains unchanged. A subsequent transactional migration creates the four operation tables, converts every old `intent_feedback` and `intent_corrections` row into a deterministic independent legacy lineage/input/event, verifies counts, IDs, text, reconstructed original JSON values, and foreign keys, then removes both old tables. Generic JSON decoding preserves unknown fields and enum values. Migrated text and determinable final target move into normalized columns; remaining original values are retained as versioned legacy details.

Legacy observations never manufacture attempts, presentation history, retries, acceptance, or execution duration. Their context is `legacy_partial`; missing facts stay absent. Any malformed row rolls back the entire migration, retaining the old tables. Reopening does not duplicate migration, and migration itself never expires history.

Jotway uses its own `Jotway/jotway.sqlite` location and does not import another application's data or credentials.

## Derived Notes index

Related History uses a separate `Jotway/notes-index.sqlite`, independent of operation records and launcher migrations. `NotesIndex` serializes database work away from the main actor. Its own `v1_notes_index` migration creates source metadata/read status, chunk plaintext with ordinal and UTF-16 offset, text hashes and conservative `recorded_in_note` provenance, a vec0 Float32 cosine table, and an index-state row for profile, publication version, completed-batch checkpoint and last successful reconciliation time. Shared notes keep their shared flag; no authorship inference is stored.

The profile includes provider, endpoint, model, dimension and processing version. A processing-only version upgrade atomically deletes old vectors/chunks, marks source rows for reprocessing and advances the publication version. Unchanged ready metadata is reread on the next permitted sync. Other profile mismatches require explicit clear/rebuild; old vectors are never mixed. Source/chunk/vector replacement and deletion are transactional. Completed batches survive cancellation/restart; subsequent scans reuse metadata only at the current processing version and reuse current paragraph hashes. Clearing vacuums derived content and pauses automatic rebuilding, without touching Notes or operation records. This is a rebuildable local cache containing sensitive plaintext, not a backup. The database file is restricted to the current user. The embedding key lives only in the separate restricted credential file. Missing notesHistory.enabled defaults to true, while saved off values remain authoritative. notesHistory.started records that preparation has begun; notesHistory.paused persists cancellation or clearing until explicitly resumed. A legacy explicitly saved started=false is treated as a pause. Automatic readiness checks require a current Notes grant, saved key, enabled history, nonempty scope and no pause; they do not migrate or rebuild the database merely on a question.


The `v2_original_boundaries` migration adds per-source processing versions and an `origins` ledger in the same database. Each origin stores a pending token, optional confirmed note ID, format version, and hashes/character lengths of whitespace-normalized original and generated tail. It stores no original or generated text. Staging occurs before create; recognizable legacy notes acquire records during extraction. Pending ownership requires a complete original-and-tail match; a tail-only suspicion is skipped without binding a note ID. Definite non-writes discard pending records; unknown outcomes retain them. Known mismatches are skipped with an ambiguous-boundary status, including edits that retain the old original prefix. Processing version 3 invalidates older derived data before reprocessing. Clear Index removes derived plaintext, vectors and source rows but preserves origin fingerprints so later rebuilding cannot recycle generated text. Migration never modifies the enabled/started preferences or resumes indexing after Clear Index.

## Daily Notes management

`NotesDailyGroupingStore` owns a separate `notes-daily-grouping.sqlite`, independent of history enablement, Clear Index and operation-record retention. Its directory is restricted to the user and its database file uses mode 0600. WAL permits concurrent reads during a refresh; competing database writers wait at most five seconds. Database failures never authorize another uncertain external write.

| Table / migration | Stored facts |
|---|---|
| `daily_groups` / `v1_daily_grouping` | Stable group/note IDs, destination, local day/time zone, original/generated revisions, conflict flag, grouped/independent layout, title status and retry metadata, ordered entry identities/timestamps, and full-body/region hashes and lengths |
| `daily_pending` / `v1_daily_grouping` | Unique operation/group IDs, create/append/refresh/title kind, prior body hash and expected next snapshot |
| `daily_entries` / `v1_daily_grouping` | Stable entry ID, owning group and sequence |
| `daily_entries.notified` / `v2_completion_receipts` | Atomic one-time completion-notice claim after confirmation |

The stable submission identity combines the draft ID and normalized-original digest, so restoring the same failed draft does not append twice. A distinct draft with identical text is a distinct entry. These tables hold no original or generated body copy. Notes is the content source; recovery requires a complete readback match. Pending records precede external writes, confirmed transactions publish identities, and uncertain outcomes remain pending rather than being blindly retried. Only current-day valid work resumes.

Snapshots encode title state (`pending`, `paused`, `complete`, `conflicted`, `expired`), first-entry identity, background-round count, next-attempt timestamp and non-secret fast-configuration version. Unknown external operations remain in `daily_pending` and are reported as uncertain, never converted into permission to repeat a write. Legacy snapshots decode missing layout as grouped and missing title metadata as already complete; they are not backfilled. Independent ordinary notes are excluded from grouped candidates. Title state and schedule survive restart without storing a body copy.

A title operation must preserve the exact entry identities, original/generated revisions and every non-title region. Append/refresh operations cannot change title metadata or its boundary; a successful title transition is accepted only from a pending or paused snapshot. Schedule changes use compare-and-swap against the current snapshot and cannot supersede unresolved writes. The module FIFO serializes these metadata changes with writes. Same-day recovery reads the first original from the confirmed Notes body, then adopts into the latest complete version so later appends and supplements survive. Old-day tasks expire without touching Notes. The durable `model.credentialRevision.<provider>` preference is a counter, never a credential or digest of a secret.

The Notes index's `v3_daily_original_boundaries` migration adds `daily_origins`: pending token, optional confirmed note ID, intended target ID and encoded daily boundary. A boundary hashes the complete line-ending-normalized body and ordered title, metadata, original and generated regions, retaining original entry IDs and lengths. It does not collapse original whitespace. Confirmation replaces the previous boundary for the same note, retires obsolete chunks/vectors and advances index publication. Unproven or mismatched daily boundaries are ambiguous; title text alone never permits truncation. Clear Index preserves both origin ledgers and the independent grouping database, so rebuilding cannot index generated content or lose management identities.

## Personal Agent memory and recording

`PersonalAgentConversation` owns ordered questions and typed replies in memory only. A reply contains fact/suggestion/to-verify items, app-owned source evidence and coverage reports. These types, source snapshots, `ActionInput.conversationContext` and full provider payloads have no database tables, export path or restart restoration. Closing or changing configuration revokes that memory. Follow-up drafts are cleared only when ending an active conversation; ordinary hidden drafts retain their existing behavior.

The existing input/attempt/event pipeline still records user-entered questions and unsent input when enabled. Personal Agent success records `completed`; cancellation/failure uses existing execution status and bounded reason codes. Retry records a new attempt linked to the failed attempt when its recording token is still current, without recording the unrelated new draft as that retry's input. No AI answer, source title/body or request payload is added to operation context or event details. Source toggles, all-readable/custom scope modes and selected container IDs use Personal Agent-specific `UserDefaults` keys. Absent source preferences use available sources; existing booleans remain authoritative. Absent legacy selection keys migrate to all-readable mode, while saved arrays (including empty arrays) migrate to custom mode. Explicit mode keys preserve subsequent choices. Configuration scope tokens are ephemeral execution identity, never operation facts.

## Clipboard history

`ClipboardHistoryStore` owns `Jotway/Clipboard/clipboard.sqlite` in Application Support, separate from `jotway.sqlite` and `notes-index.sqlite`. Its `v1_clipboard` migration creates `clips`: ID, representation type, SHA-256 digest, original payload, text, thumbnail, dimensions, copy time, OCR state/text/version and logical byte count. Byte equality after digest matching confirms deduplication. List reads exclude original image blobs. Restore verifies ID and digest before reading the original representation.

Limits are 200 entries and 200 MiB of payload, text, thumbnail and OCR bytes. Oldest entries are deleted with their derived data. Single text/image limits and OCR behavior are defined in [Clipboard](../integrations/clipboard.md). The database uses restricted file permissions and secure deletion. Clear closes and removes the database and sidecars, recreates its schema, and advances the history generation. Old captures, OCR results and confirmations cannot publish into that generation. Operation-record cleanup never clears Clipboard history.
