# AI capability

> Role: **Current**

Jotway has two AI-related paths with different responsibilities:

1. Jev suggests the destination action. It is documented separately.
2. An action text processor may clean the body before a storage action writes. Reminder and Calendar time interpretation is local and separate.

## Action text processing

Apple Notes, Reminders, and Calendar can each enable an `AITextProcessor` fixed to the DeepSeek source:

- Notes: clean the wording and put a concise title on the first line.
- Reminders: clean the reminder wording.
- Calendar: clean the event wording.

Each action has an independent enable switch and user-editable body style instruction. Disabling the processor uses the original text. Reminder and Calendar schedules always come from the original draft through the local deterministic resolver; model output and style instructions cannot change those frozen times. Notes can append a fixed `#标签` text line and, while AI rewrite is enabled, ask the processor for related tags.

This processor is independent of the general source selected on the AI settings page. Missing key, network error, timeout, empty response, or invalid body output falls back to the original text. Cancellation propagates. Body fallback never alters time interpretation or turns a blocked time into a writable request.

## General provider configuration

All builds register DeepSeek and Moonshot through the shared provider installation. Settings save the source/model choice, key, manual Instructions, and prompt configuration; a connection test uses fixed sample content.

Configuration is frozen before a logical request enters the queue. Changing settings affects new requests, not one already queued or running.

## Safety boundaries

- Requests have a bounded encoded size.
- Provider calls are serialized by the shared actor.
- A configured model must be confirmed by a valid returned model identifier; a mismatch discards the result.
- Cancellation propagates through queued and running work.
- Runtime logs record bounded stages, identifiers, outcomes, and timing without draft text or keys.

Provider transport details are in [AI provider implementation](ai-provider-implementation.md).
