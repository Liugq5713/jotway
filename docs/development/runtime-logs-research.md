# Runtime logs

> Role: **Current**

Jotway writes bounded JSONL diagnostics for application lifecycle, intent recognition, AI, and external action calls. Logs support failure investigation; they are not an activity history.

## Privacy boundary

Logs use allow-listed identifiers, result codes, stage names, durations, and bounded diagnostic fields. Draft text, API keys, complete provider responses, and account details are excluded.

Historical Personal Agent full-content archives remain untouched in Application Support. Current Notes model calls do not create or append these archives; runtime-log export and cleanup remain separate.

The writer accepts only the current fixed diagnostic enums. Unknown historical enum values may be decoded as the canonical `unknown` state when reading retained feedback, but arbitrary raw values are never admitted to new log events.

A missing completion event cannot prove success. The UI marks logs incomplete when queued events were dropped or storage became unavailable.

Clipboard original text, image data, thumbnails and OCR never enter RuntimeLog or operation-record exports. Clipboard queries follow the ordinary operation-record preference, while local confirmation records only query context and execution status. OCR helper failures return a fixed error without printing file paths, recognized text or system descriptions. Clipboard storage and its clear action are independent of both log systems.

## Storage and retention

- Directory: `~/Library/Logs/Jotway`
- File pattern: `jotway-YYYY-MM-DD.jsonl`, with numbered volumes after rotation.
- Retention: today plus the previous six days.
- Limits: 10 MB per file and 50 MB total.
- Directory permissions: current user only.

Logging failure never blocks the main action path. Later events retry preparation automatically.

## User controls

Settings → General → Troubleshooting → App Logs is collapsed by default, with its scope description always visible. It can:

- show current size and completeness;
- open the log directory;
- export retained logs as ZIP;
- clear retained logs without changing drafts or preferences.

Local Records appears separately in the same Troubleshooting section. Its text capture, retention, export and deletion controls do not affect App Logs; clearing App Logs also preserves Local Records.

Export copies retained complete JSONL lines without decoding or rewriting them, including historical Jev metadata without adding a current rule definition. Compatibility decoding remains isolated from live local application diagnostics.

Related History does not log source bodies, queries, source IDs, embedding responses or embedding credentials. Its local derived index intentionally contains selected plaintext; Clear Index is separate from runtime log and operation-record clearing. Retrieved snippets can be sent to the existing content-generation service only through the enabled Notes assistance path.

## Notes assistance diagnostics

Confirmed Notes saves propagate their action request identity through deferred preparation, generation and adoption. Provider calls retain a separate call ID; Notes calls explicitly use the supplement purpose without changing prompt selection. The adoption event includes the generated UUID of the native create request, not a source note ID. A create attempt or adoption event is not proof of a confirmed save.

The fixed `notes` diagnostic structure records retrieval state, raw and distance-qualified chunk counts, eligible distinct-source count, actual candidate count/bytes and scoped numeric coverage. Counts that were never obtained are absent, not zero. No source or folder identifiers, titles, excerpts, queries, raw errors or model responses are included.

`notes_retrieval` reports retrieval separately from generation. `notes_preparation` is emitted once for the winning preparation result: disabled, missing configuration, generated, history-only, valid empty, invalid output, provider error, timeout, stale or cancelled. Rejections distinguish schema, cardinality, length, source, evidence and duplication. Tolerated formatting and skipped entries do not fail a preparation with valid remaining content; item/history counts describe the accepted result. If all supplied entries are unusable, the first rejection reason is retained. A late provider transport result cannot emit a second preparation terminal result.

`notes_adoption` reports the actual item/history counts carried by the create request, distinguishing applied/empty content, renderer filtering and unavailable provenance. This preserves the difference between successful generation and actual adoption. Numeric fields are bounded before logging; normal retention, incomplete-log reporting and best-effort writes remain in force.

Daily grouping adds `notes_grouping`, `notes_original_save` and `notes_refresh` stages. Grouping reports success or a bounded fallback code (budget, format, model, availability or timeout); original confirmation and optional refresh failure remain separate outcomes. Refresh reports discarded/cancelled/stale work without reporting the original as failed. These events contain no project title, original, classification rationale, source body, note/folder ID or credential.
