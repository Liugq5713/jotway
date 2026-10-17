# Third-party notices

> Role: **Reference**

Jotway uses the following dependencies. Their original copyright notices and license terms remain applicable to their code.

| Dependency | Source | License |
|---|---|---|
| GRDB.swift | https://github.com/groue/GRDB.swift | MIT; pinned source contains `LICENSE` |
| Sparkle | https://github.com/sparkle-project/Sparkle | Permissive license with bundled third-party notices; see the distribution's `LICENSE` |
| KeyboardShortcuts | https://github.com/sindresorhus/KeyboardShortcuts | [MIT](Vendor/KeyboardShortcuts/license) |
| Geist (website font) | https://github.com/vercel/geist-font | [SIL Open Font License 1.1](website/src/fonts/OFL.txt) |

`Package.resolved` pins downloaded dependencies. `Vendor/KeyboardShortcuts` contains local build and recorder-layout changes; its upstream copyright and license are preserved.

`build-app.sh` includes all three complete license files in `Jotway.app/Contents/Resources/Licenses/`. Jotway's own source code is licensed under the GNU General Public License v3.0; see [`LICENSE`](LICENSE).

The website self-hosts the unmodified Geist variable webfont from upstream release v1.7.2. Its license and [source provenance](website/src/fonts/provenance.json) are copied alongside the font to `assets/fonts/`; the font is not bundled in `Jotway.app`.

## sqlite-vec v0.1.9

- Source: https://github.com/asg017/sqlite-vec/releases/tag/v0.1.9
- Release amalgamation: `sqlite-vec-0.1.9-amalgamation.tar.gz`; upstream source identifier `e9f598abfa0c06b328d8fe5da9c3760cce74be10`.
- Copyright Alex Garcia. Used under the MIT license; full text is in `Vendor/sqlite-vec/LICENSE-MIT`.
- `sqlite-vec.c` and `include/sqlite-vec.h` come from the release amalgamation; six trailing-whitespace occurrences in the C source are removed for repository whitespace checks. No functional upstream code is changed. SwiftPM builds `CSQLiteVec` with `SQLITE_CORE` and links the same system SQLite used by GRDB. No second SQLite implementation or loadable extension is bundled.
