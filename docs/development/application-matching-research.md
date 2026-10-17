# Application matching research

> Role: **Reference**
>
> Research date: 2026-10-09. Raycast public documentation and Tinycast source comparison for Jotway's application matching. This is evidence and design guidance, not an implementation specification.

## Finding

Both launchers support matching beyond the beginning of an application's name. **Abbreviation matching does not imply spelling correction**: Tinycast's current matching code accepts `settings`, `sett`, `ss`, and `sysset` for System Settings, but rejects `settting`. Raycast documents abbreviation matching; its behavior for that misspelling remains unverified. [Raycast search](https://manual.raycast.com/search-bar), [Tinycast matching][tc-match]

## Evidence boundary

- Raycast: official manual and changelog; no inspection of its private core implementation and no installed-app UI test. Do not infer a particular edit-distance algorithm or promise that `settting` works.
- Tinycast: public `main` resolved to commit [`9e6beba99aacedf50bbf42c1a5107b981ffb37ab`](https://github.com/abue-ammar/tinycast/commit/9e6beba99aacedf50bbf42c1a5107b981ffb37ab). The matching experiment compiled its original Swift files in a temporary folder; no competing app or Jotway app was launched.
- Tinycast's [deployed manual](https://tinycast.dev/docs/launcher/) and [current repository documentation][tc-doc] differ. The deployed page describes the older tier-based ranking, Spotlight names and bundle-identifier search. The pinned current launcher uses `LauncherMatch`, `SearchProfile`, sensitivity thresholds and a comparator. This document follows pinned code where those sources disagree; it does not establish which version is installed or released.
- Jotway findings refer to the current working tree. Pre-existing unrelated changes were preserved; this research makes no application-code changes.

## Raycast: documented behavior

| Mechanism | Evidence |
| --- | --- |
| Fuzzy application names | `msg` finds Messages and `slk` finds Slack; matching is not restricted to a contiguous name prefix. |
| Alternate names | System Settings can be found by Preferences; the manual describes alternate names and Spotlight keywords. |
| Ranking | The documented ladder is exact alias, alias prefix, title fuzzy score, subtitle/keyword matches, then frecency. Previous choices for a query influence future ordering. |
| Sensitivity | High is stricter, Medium is the default, and Low admits weaker matches. |

Source: [Raycast Search Bar](https://manual.raycast.com/search-bar). Finding System Settings with `settings` is consistent with this description, but was not verified in the running app. No inspected official source establishes the result for `settting`.

User-defined aliases have a separate contract: exact and prefix matching, without fuzzy matching. [Command Aliases & Hotkeys](https://manual.raycast.com/command-aliases-and-hotkeys)

The 1.40.0 changelog introduced fuzzy Root Search in September 2022, with examples including `ftime` → FaceTime and `msg` → Messages, alongside ranking influenced by prior use. This is historical evidence, not the current algorithm's source. [Raycast 1.40.0](https://www.raycast.com/changelog/1-40-0)

## Tinycast: current matching path

1. **Build searchable names once.** The scanner reads localized bundle names, the file name and `CFBundleAlternateNames`; declared application names become keywords. `EntryNaming` keeps title, alternate titles, subtitle and keywords separate. Current launcher fields do not include bundle identifiers or executable names. [Scanner][tc-scan], [EntryNaming][tc-naming], [current field contract][tc-doc]
2. **Normalize and align.** Case, accents, width and invisible format characters are normalized. Script-specific romanization supports Latin input. The matcher finds an ordered alignment, allowing gaps while rewarding word boundaries, camel-case boundaries and adjacency. This is subsequence matching, not general typo correction. [Normalization][tc-normalize], [romanization][tc-romanize], [matcher][tc-match]
3. **Filter weak matches.** Exact text passes. Medium, the default, requires `score ≥ 1.5 × (L − 2) + 4`; High requires `score > 2 × L`; Low accepts any valid alignment. `L` excludes skipped query separators. [Sensitivity][tc-sensitivity]
4. **Rank eligible entries.** Exact user aliases lead. After the special AI Chat boost rule, exact titles/alternate titles for queries longer than three characters receive protection. Prior query matches, subtitle equality and alias prefixes precede general fuzzy scores; frecency and stable tie-breaks follow. Keywords can admit a result but do not contribute a ranking score. The full comparator includes exceptions, so it is not one universal additive score. [Candidate admission and comparator][tc-order]
5. **Remember use locally.** Each visit adds 100 to a score that halves every ten days. Up to three recent search terms per entry can steer ranking for 408 hours after the last open. Ranking does not make an otherwise unmatchable name eligible. [Usage store][tc-usage], [admission guard][tc-order]

### System Settings experiment

The harness compiled the pinned `SearchRelevance.swift`, `ScriptRomanization.swift`, `LauncherMatch.swift`, `EntryNaming.swift`, `LauncherRankingStore.swift` and `LauncherOrder.swift`, then called the real `LauncherOrder.ranked` with Medium sensitivity and unused history. It compared a title-only profile with a profile containing the actual local System Settings bundle's alternate names: `System Preferences`, `System Settings`, `Preferences`, `Settings`. It did not instantiate the persistence store or write application preferences.

| Query | Title-only match | With actual alternate names | Title score |
| --- | --- | --- | ---: |
| `settings` | Yes | Yes | 17 |
| `sett` | Yes | Yes | 9 |
| `ss` | Yes | Yes | 6 |
| `sysset` | Yes | Yes | 14 |
| `settting` | No | No | No alignment |

These are executed source-level results, not screenshots or full application acceptance. Alternate name `Settings` also makes `settings` an exact alternate-title hit, strengthening its rank beyond the title-only fuzzy score. [Name loading][tc-scan], [ranking][tc-order]

The misspelling `settting` asks for three `t` characters after `se`; no ordered alignment exists in System Settings or its actual alternate names. The matcher has no insertion/deletion/substitution-distance fallback. Omitting a character can still happen to form a subsequence: the extra probe `setings` matched. That does not establish general spelling tolerance. [Alignment precheck and scorer][tc-match]

## Implications for Jotway

The existing helper [`InstalledApplication.matchedName`](../../Sources/Features/Launcher/InstalledApplication.swift) already checks substrings, but the main [`applicationCandidates` and `applicationNameMatch`](../../Sources/Features/Launcher/IntentRecognition.swift) path prioritizes exact names and restricts short application input to prefixes. Its ambiguity resolution uses per-app open count and last-opened time. [`LauncherSession.makeIntentCandidates`](../../Sources/Features/Launcher/LauncherSession.swift) exposes the selected suggestion plus actions, setup and explicit selection rather than all matching applications.

The following are proposed directions, not current behavior or authorization to implement:

1. Use one scored application matcher for candidate retrieval and local intent recognition; include later words, substrings and ordered abbreviations.
2. Include bundle alternate names and preserve localized names and existing Chinese phonetic input support. `Settings` is useful application metadata, not a hard-coded one-off synonym.
3. Expose ranked application candidates so the user can choose among ambiguous matches. Improving retrieval alone would leave this interaction gap.
4. Treat bounded typo correction as an additional decision. To support `settting`, add a deliberately constrained fallback and rank it below accurate matches; copying Tinycast's subsequence matcher alone is insufficient.
5. Preserve ordinary draft routing and explicit selection. Broader application matching must not silently turn normal Notes content into a launch action. Query-specific ranking is a separate behavior change from the existing per-app usage ranking.

[tc-doc]: https://github.com/abue-ammar/tinycast/blob/9e6beba99aacedf50bbf42c1a5107b981ffb37ab/docs/features/launcher.md
[tc-match]: https://github.com/abue-ammar/tinycast/blob/9e6beba99aacedf50bbf42c1a5107b981ffb37ab/Tinycast/Features/Launcher/Model/LauncherMatch.swift#L77-L172
[tc-sensitivity]: https://github.com/abue-ammar/tinycast/blob/9e6beba99aacedf50bbf42c1a5107b981ffb37ab/Tinycast/Features/Launcher/Model/LauncherMatch.swift#L175-L203
[tc-naming]: https://github.com/abue-ammar/tinycast/blob/9e6beba99aacedf50bbf42c1a5107b981ffb37ab/Tinycast/Features/Launcher/Model/EntryNaming.swift#L6-L30
[tc-scan]: https://github.com/abue-ammar/tinycast/blob/9e6beba99aacedf50bbf42c1a5107b981ffb37ab/Tinycast/Features/Launcher/Service/AppIndex.swift#L620-L647
[tc-normalize]: https://github.com/abue-ammar/tinycast/blob/9e6beba99aacedf50bbf42c1a5107b981ffb37ab/Tinycast/Features/Launcher/Model/SearchRelevance.swift#L114-L128
[tc-romanize]: https://github.com/abue-ammar/tinycast/blob/9e6beba99aacedf50bbf42c1a5107b981ffb37ab/Tinycast/Features/Launcher/Model/ScriptRomanization.swift#L14-L28
[tc-order]: https://github.com/abue-ammar/tinycast/blob/9e6beba99aacedf50bbf42c1a5107b981ffb37ab/Tinycast/Features/Launcher/Model/LauncherOrder.swift#L138-L260
[tc-usage]: https://github.com/abue-ammar/tinycast/blob/9e6beba99aacedf50bbf42c1a5107b981ffb37ab/Tinycast/Features/Launcher/Model/LauncherRankingStore.swift#L21-L132
