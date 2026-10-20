# Proposal

## Why

Saving a draft currently generates AI Insights or refreshes extra content in a saved note. The user wants Notes to collect their own words by related topic, without adding AI analysis to the body.

## What Changes

- **BREAKING**: Remove Notes AI Insights / Add Extra Ideas, supplement generation, grouped supplement refresh, and their dedicated settings and prompts. Old enabled preferences cannot restore these features.
- Keep daily related-topic grouping, original-text saving, automatic initial titles and same-day title recovery. Keep read-only today/weekly reviews and draft thinking prompts, as explicitly confirmed by the user.
- Save new notes with a title and complete originals only; grouped notes keep the existing compact timeline. Do not wait for the removed supplement request.
- Preserve existing saved AI content and its verified boundaries as legacy data. No cleanup sweep, new insight, refreshed analysis, or new stale-analysis notice is allowed. A safe append retains that old tail; uncertain boundaries protect the old note and use the existing independent-save fallback.
- Retain existing source-link opening, original extraction, write guards, uncertain-write reconciliation, and completion behavior. Keep old preferences inert rather than deleting user settings.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `notes-ai-assistance`: Replace active supplement requirements with a firm no-supplement contract, settings removal, and explicit retained features.
- `notes-ai-presentation`: Define original-only new output and compatibility for already saved generated sections.
- `notes-daily-grouping`: Remove refresh scheduling and recovery while retaining grouping, title recovery, safe writes, and legacy-tail preservation.
- `model-capabilities`: Remove supplements from consumer examples while preserving shared model routing and review streaming.

## Impact

Implementation touches `AppleNotesAction`, `NotesDailyGroupingCoordinator`, supplement-only processors/results, Notes rendering, Notes settings and Writing Preferences, plus localized strings and Current docs. `NotesOriginStore`, `NotesDailyBoundary`, and the daily management ledger remain necessary for reviews and safe updates. Serialized legacy refresh records must remain readable; removing generation must not erase evidence of an uncertain write.

The working tree already has extensive source and documentation changes. This proposal uses that current tree as its baseline and does not revert, implement, commit, or install anything. Verification during apply uses a build and affected existing tests with isolated data; real Notes display remains manual acceptance unless separately requested.
