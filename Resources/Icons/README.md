# Jotway icon sources

> Role: **Reference**

`AppIcon.png` is the original illustration generated with the built-in image generation tool. It depicts a silver-blue folded note on a graphite tile, with transparent margins. `MenuBarIcon.svg` is a simplified, monochrome interpretation of the same note for the macOS menu bar.

Run `./scripts/build-icons.sh` from the repository root to export all macOS icon sizes to `Resources/AppIcon.icns` and the 18 pt menu template to `Resources/JotwayMenuBarTemplate.pdf`. Export uses macOS `sips` and `iconutil`, plus `rsvg-convert` for the vector menu template. Normal app builds use these checked-in exports.

## Generation prompt

```text
Use case: logo-brand
Asset type: production macOS application icon for Jotway, square 1024 x 1024 PNG.
Primary request: draw a distinctive pictorial icon, with NO letter or monogram. The app turns a quickly written thought into the next action.
Subject: a single sculptural folded note, poised diagonally toward the upper right; a broad simple rectangular note surface and one sharply folded corner suggest a thought being sent forward. Two short recessed strokes on the broad face subtly suggest writing. The note should read as one coherent tangible object, not a letter and not a generic paper airplane.
Style/medium: premium minimal icon illustration with restrained shallow 3D depth, precise chamfered edges and clean large planes. Quiet futuristic industrial design.
Color palette: dark graphite rounded-square tile; icy silver and electric blue folded note, with a small cyan edge highlight. No warm colors.
Composition: centered, immediately legible silhouette at 32 pixels. Tile fills approximately 82% of canvas, equal transparent margins, rounded corners. The note fills about 65% of the tile. Front-facing tile, gentle perspective on the note only.
Lighting: soft studio light, controlled contrast, subtle edge glow only. Smooth graphite surface without noise.
Background: genuine transparent alpha outside the tile, including its corner cutouts. No scene or mockup.
Constraints: one icon only; no text, no letters, no J or S shapes, no wordmark, no watermark, no circuitry, no particles, no extra objects, no grid, no tiny detail, no excessive neon, no checkerboard painted into background.
```
