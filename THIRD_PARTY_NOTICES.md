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
