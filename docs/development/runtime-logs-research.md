# Runtime logs

> Role: **Current**

Jotway writes bounded JSONL diagnostics for application lifecycle, intent recognition, AI, and external action calls. Logs support failure investigation; they are not an activity history.

## Privacy boundary

Logs use allow-listed identifiers, result codes, stage names, durations, and bounded diagnostic fields. Draft text, API keys, complete provider responses, and account details are excluded.

The writer accepts only the current fixed diagnostic enums. Unknown historical enum values may be decoded as the canonical `unknown` state when reading retained feedback, but arbitrary raw values are never admitted to new log events.

A missing completion event cannot prove success. The UI marks logs incomplete when queued events were dropped or storage became unavailable.

## Storage and retention

- Directory: `~/Library/Logs/Jotway`
- File pattern: `jotway-YYYY-MM-DD.jsonl`, with numbered volumes after rotation.
- Retention: today plus the previous six days.
- Limits: 10 MB per file and 50 MB total.
- Directory permissions: current user only.

Logging failure never blocks the main action path. Later events retry preparation automatically.

## User controls

Settings → 通用 → 日志 can:

- show current size and completeness;
- open the log directory;
- export retained logs as ZIP;
- clear retained logs without changing drafts or preferences.

Export copies retained complete JSONL lines without decoding or rewriting them, then adds the active Jev rule definition so intent events can be interpreted against the correct rule version.
