# Design

## Context

See `proposal.md` for the user problem and `specs/launcher-appearance/spec.md` for the behavior contract.

Current source evidence:

- `RecordPanelPlacement.origin(for:on:savedOffset:)` already computes the default frame from `visibleFrame`: centered X, top inset of 18% of usable height, then screen constraints. Saved offsets are measured from the usable top-left. Its screen snapshots already include a display ID and global point coordinates.
- `RecordPanel` has `beginUserDrag`, `moveForUserDrag`, `endUserDrag`, and `cancelUserDrag`. Native background movement enters through window delegate notifications. `WindowDragNSView.mouseDown` in `EditorView.swift` uses a manual pointer-delta loop and calls those methods explicitly. Neither path currently draws guides or aligns the final frame.
- `endUserDrag` currently saves the raw dragged frame before applying final screen size constraints. Alignment must move this write after the final frame is settled.
- `isAdjustingFrame` protects programmatic movement; `dragStartOrigin`, `draggedFrame`, and a local mouse-up monitor identify user movement. `windowDidMove` also detects a released button. Multiple end calls are possible and must remain harmless.
- Quick input offsets use `AppState.recordPanelPositions`; sticky mode keeps independent process-local geometry. `temporary-draft-mode` requires existing first-entry and restoration behavior. No change to that contract is needed.
- `JevPanelTests` provides an offscreen panel fixture with a separate defaults suite, in-memory database and mock Notes client; existing width checks cover editor resizing. No dedicated placement or drag tests were found. Do not add tests without a new user request.

## Goals / Non-Goals

**Goals:** Keep one geometry calculation and one drag lifecycle for both paths. Make the guide display a small output-only component. Keep ordinary drag performance independent of SwiftUI layout and preference writes.

**Non-Goals:** No previous-position history, custom home position, reset command, screen-edge tiling, alignment to other applications, resize guides, new drag handle, settings toggle, or change to screen selection on opening. No app launch or automated UI driving during planning.

## Decisions

### 1. Reuse default geometry and compare center X / top Y

Add a small side-effect-free alignment calculation beside `RecordPanelPlacement`. Given an unaligned frame, screen snapshots and prior drag screen ID, return the active screen, default frame, per-axis active flags and release frame. Compute the default using the existing origin function with `savedOffset: nil` and the current constrained size. Compare `midX` and `maxY`, using AppKit global points throughout. This avoids treating the varying panel height or lower card as a center-Y target.

Select the screen from the largest intersection of the raw frame and each display's full frame. Preserve the previous drag screen on a tie; otherwise use snapshot order. Use that chosen display's `visibleFrame` for default placement and guide clipping. Do not read the opening-screen preference during a drag. If no display intersects, return no guide or snap target. Avoid changing screen-selection behavior for unrelated callers merely to add this tie policy.

Alternative: duplicate a centered formula in a view. Rejected because default opening and drag return could drift apart, especially on small screens or with a Dock on one side.

### 2. Preview alignment and snap on release

Both faint guide lines appear after actual movement starts. An axis within 8 pt inclusive gets an active style. Movement itself stays pointer-relative; final release uses the same eligibility calculation and aligns only active axes without animation. This proposed tolerance is a bounded design choice, not a measurement of Raycast.

Alternative: continuously snap while moving. Rejected for this version because it can fight native dragging and produce pointer jumps. Guide-only feedback would still require pixel-level aiming, so use a small release snap.

The geometry result is authoritative for both highlight and release. Recompute when size changes during a drag, and apply existing size constraints before final alignment. Save only the resulting actual frame. Retain top-edge anchoring when lower content changes. Do not reset width, manual-height policy, or open lower content to reach the target.

### 3. Use a lightweight AppKit guide overlay

Add a `RecordPanelDragGuides` owner in `Sources/Window/` with one lazily created transparent borderless panel for the active screen. It cannot become key or main, ignores mouse events, has no shadow, and has no accessibility elements. Its lifetime belongs to the record panel and it uses compatible Space/fullscreen behavior without opening another Space.

Draw two thin lines clipped to the usable screen. Mask the record panel frame with a small gap so guides do not cross text, cards or their transparent gap. Use a subtle contrasting halo to remain visible on varied desktop backgrounds without reading those backgrounds. Use dashed inactive lines and solid, stronger active lines; theme and Increase Contrast select colors and strength. No pulsing, spring, fade, screenshot, or screen-recording permission is needed. Reduce Motion therefore needs no separate motion path.

Update the existing overlay's frame and drawing only when geometry or style changes; never construct one window per mouse event. When the target screen changes, move/update this single overlay and clear the previous drawing immediately.

Alternative: SwiftUI lines inside the editor. Rejected because those lines cannot show the screen target outside the window and can affect input layout. A full desktop dimmer is unnecessary for two guides.

### 4. Make normal completion distinct from cancellation

Keep drag ownership in `RecordPanel`. Both native notifications and the custom pointer loop feed one update method after recording the raw frame. Show guides only after the frame actually moves, not at `windowWillMove` or a plain click. Never start from `didMove` alone. Exclude live resizing, animation and `isAdjustingFrame` movements.

On normal completion: capture the active gesture, calculate the release result, retire that gesture and remove its monitor/overlay, apply constraints and alignment under `adjustingFrame`, then write the final position once through the current mode's path. Clear `stickyLowerAreaBaseFrame` as normal user movement already does. Repeated mouse-up/deferred end calls must be no-ops.

On cancellation: retire the gesture and remove the overlay/monitor without snapping or saving a drag offset. Include `close`, `orderOut`, `hideForGettingStarted` (which currently bypasses `orderOut`), mode transitions, submission/hide animation entry, display changes and loss of the active drag. Guard the custom loop so late events from a cancelled gesture cannot call `beginUserDrag` and start a new gesture before the next mouse-down; a small gesture generation/token is suitable. A mouse-up whose window identity differs must still end the owned gesture. If a release cannot be observed reliably, cancel rather than leave guides behind or commit a stale position. Remove any added observer/monitor on disposal.

Alternative: snap in every `windowDidMove`. Rejected because native and programmatic moves share that callback and it would affect animation, automatic growth and restored positions.

## Risks / Trade-offs

- Native drag event ordering differs from the custom loop → Share updates and an idempotent completion path; manually check both paths and interrupted drags. Do not claim runtime acceptance from a build alone.
- A translucent guide can disappear over a desktop background → Use a contrast halo and line-pattern state, then manually check light/dark backgrounds and Increase Contrast.
- Screen changes or lower-card growth can invalidate a target → Compute from current geometry, cancel on display-configuration changes, and save the actual final constrained frame.
- Eight-point release snapping slightly changes free placement near the default → Limit it per axis, show eligibility before release, and leave all other positions free. No new preference is needed for this first version.
- Native overlay ordering in fullscreen Spaces needs real-window evidence → Match the existing panel's Space behavior and explicitly include this in manual acceptance.

## Migration Plan

No data migration or new preference key is needed. Implement the helper, overlay and drag integration, run `swift build` and suitable existing non-UI checks, and update the current product overview after the behavior is implemented. Document unperformed real-window checks separately. Do not launch or drive the installed app without explicit authorization. Rollback removes guide/alignment code; saved offsets remain valid ordinary positions in the existing format.
