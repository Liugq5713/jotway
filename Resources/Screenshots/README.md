# Product image capture

> Role: **Reference**

Current README pages omit screenshots until regenerated and visually reviewed against the intended source build. Retired Chrome-search captures are not product evidence.

```bash
python3 scripts/website/render-screenshots.py
swift scripts/website/ComposeFlow.swift Resources/Screenshots
```

The renderer builds and links an isolated entry point to the production `EditorView`, using fictional Notes text in offscreen light/dark hosts. It never starts JotwayApp, orders a window on screen, instantiates AppState, reads Notes or credentials, enumerates applications, or executes an action. It writes source hashes to `provenance.json`.

The composer uses only those local images to show two stages: empty input and fictional Notes input before confirmation. It does not open a browser or capture a destination application. It never proves a successful save. Before adding images to either README, inspect the generated output at narrow widths and compare source hashes with the intended release. A current source preview does not certify an older downloadable release.
