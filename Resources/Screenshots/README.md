# Product image capture

> Role: **Reference**

These are real production-view captures and a real browser crop, with synthetic example text. No AI-generated UI, private draft, account name, credential, calendar event or application list is included.

On macOS with the repository's Swift toolchain:

```bash
python3 scripts/website/render-screenshots.py
swift scripts/website/ComposeFlow.swift Resources/Screenshots
```

The first command builds the debug product, links an isolated `RenderScreenshots` entry point, and captures the actual `EditorView` through an offscreen `NSHostingView`. It never runs `JotwayApp` or its startup path and never orders a window on screen. It uses the system's current accessibility appearance settings, with explicit light/dark appearances for the captures. The UI remains English while input text can be any supported language.

The flow uses the synthetic input `Google search macOS keyboard shortcuts`. The Chrome Action passes that complete string into its Google search URL. `chrome-search.png` was captured from that real page in Chrome; only the logo, synthetic query and navigation strip are included. Re-capture that area using an isolated browser tab if Chrome's presentation or the input changes. Exclude profile controls, account identity, location, personal results, and browser history. Use at least 2× capture resolution. The current crop is the 890 × 128 point area at x=166, y=16 of the desktop page, captured at 2× through Chrome's screenshot scale (3560 × 512 pixels on the capture display).

The second command uses AppKit to place the unmodified screenshots and descriptive annotations on a 1440 × 1240 pixel canvas. It does not recreate or repaint the product UI. Both language READMEs reference this same file and explain that the three frames are a staged walkthrough, not an execution recording or a history feature.

`provenance.json` contains hashes of the UI sources used by the renderer. Before including these images with a release, compare those sources to the intended release checkout, inspect light/dark images and the flow at narrow README widths, and regenerate if needed. Current local sources can be captured before a public package exists; that does not certify compatibility with an older package.
