# Proposal

## Why

After moving the quick record panel, users cannot easily return it to its default opening position by eye. Drag guides with a small release snap make that position visible and easy to reach. The user confirmed that the target is Jotway's default position, not the position before a drag.

## What Changes

- Show two quiet screen guides during a real panel move: the default horizontal center and the default top edge. Use the current screen's usable area and the existing default placement calculation.
- Highlight each axis within 8 pt of its target. On release, align only those axes; outside that range, keep free placement. The panel follows the pointer without magnetic resistance during movement.
- Support both quick input and temporary sticky note dragging, including native background dragging and the existing custom drag view. Sticky mode uses the same default alignment target for its own size; its first opening and restoration rules do not change.
- Remove guides as soon as a drag ends or is interrupted. Guides do not take focus, receive clicks, affect editor layout, or appear during resizing and programmatic movement.
- Keep per-screen quick input position storage and process-only sticky geometry. Save the final aligned position through the existing mode-specific path.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `launcher-appearance`: Add default-position drag guides, release alignment, multi-screen targeting, and guide lifecycle requirements for the shared quick record panel.

## Impact

- `Sources/Window/RecordPanelPlacement.swift`: Reuse default placement with no saved offset; add side-effect-free alignment geometry.
- `Sources/Window/RecordPanel.swift`: Connect both drag paths to guide updates, final alignment, cleanup, and existing position storage.
- `Sources/Features/Editor/EditorView.swift`: Preserve the custom drag view's pointer-relative movement and click behavior; adjust its integration only if needed.
- A small AppKit guide overlay under `Sources/Window/`; no new dependency, permission, background service, or settings page.
- Update `docs/product/overview.md` after implementation. Existing panel checks provide regression coverage; real drag and focus acceptance remains manual unless explicitly authorized.
- Raycast is inspiration from the user's description, not a verified claim about Raycast's current implementation or exact interaction.
