# Launcher competitor research

> Role: **Reference**
>
> Research date: 2026-10-04. Official documentation review for a product discussion focused on frequent users. This is external evidence and a comparison snapshot, not an implementation specification.

## Evidence boundary

Raycast's current public manual describes v2 and links separately to a v1 manual. The v2 overview directs users to Check for Updates or the website download. The facts below refer to that public manual; they do not establish what is installed on a particular machine or what a particular account can access. No competing app was installed, opened, benchmarked, or used with real accounts. Claims about speed, recognition accuracy, Chinese-language quality, reliability, and user retention require separate measurements. [Raycast v2 overview](https://manual.raycast.com/new-in-v2)

The Jotway comparison uses the current working tree, including pre-existing uncommitted work. A **Current** document or matching code is evidence of the current repository behavior, not proof that the installed or publicly released app contains it. **Work** documents are proposals. Terminology follows [CONTEXT.md](../../CONTEXT.md).

## Raycast: predictable access and discoverable actions

| Capability | Officially documented behavior | Reference |
|---|---|---|
| Command hotkeys | A command can receive a global hotkey and launch while Raycast remains in the background. The recorder exposes conflicts. | [Command Aliases & Hotkeys](https://manual.raycast.com/command-aliases-and-hotkeys) |
| Aliases | A user-defined alias uses strict matching; an exact alias receives the highest result priority. Alias plus space focuses a command's first argument when it has one. | [Command Aliases & Hotkeys](https://manual.raycast.com/command-aliases-and-hotkeys) |
| Favorites | Commands, applications, or items can be pinned and reordered above other results when Root Search is empty. | [Search Bar](https://manual.raycast.com/search-bar) |
| Action Panel | The selected item has contextual actions. Enter runs its primary action; Command-K opens an action list that can be searched and shows shortcuts. Actions may open submenus rather than immediately execute. | [Action Panel](https://manual.raycast.com/action-panel) |
| In-context customization | A command's hotkey and alias can be configured from its Action Panel, without first navigating to Settings. Items expose different operations, such as opening a file, choosing another app, revealing it, or copying its path. | [Action Panel](https://manual.raycast.com/action-panel) |

Product interpretation: these mechanisms let users move from discovering a command to repeatedly invoking it through a stable path. This is a design inference; the documentation does not measure the resulting time savings.

## Raycast: reusable personal commands

Quicklinks make website URLs, search URLs, file or folder paths, and application deep links searchable by name. Users can choose which app opens a link. Search URLs may include an argument supplied when the command runs. Quicklinks can also use current clipboard content, selected text, dates, or other supported dynamic values. [Quicklinks](https://manual.raycast.com/quicklinks)

Dynamic placeholders are shared building blocks across Quicklinks, Snippets, and AI Commands, with availability varying by placeholder and feature. The manual documents clipboard text, selected text, runtime arguments, and date/time forms, plus transformations such as trimming and URL encoding. Do not assume every placeholder works in every feature. [Dynamic Placeholders](https://manual.raycast.com/dynamic-placeholders)

AI Commands save a repeatable prompt as a command. Users may combine the prompt with selected text or runtime arguments, pick a model, and choose whether the response opens in Raycast or replaces the selection. The result can also be copied, pasted, or discussed further. Quick Fix applies a writing correction in the focused app and requires macOS Accessibility permission. The page marks AI Commands as **Pro Exclusive**. [AI Commands](https://manual.raycast.com/ai/ai-commands)

Product interpretation: a reusable command can capture a complete recurring operation—input source, transformation, and output—rather than only its destination application. This distinction is useful when comparing Jotway's current prefix-to-action rules with richer personal workflows.

## Raycast: context and task execution with AI

| Capability | Verified public behavior | Boundary |
|---|---|---|
| AI Extensions | In Quick AI, AI Chat, or Root Search, a user can mention an installed extension and describe an action. The model selects tools and arguments. The documented built-ins include creating/searching/completing Apple Reminders, file operations, calendar queries, clipboard search, and terminal commands. A prompt may combine several extensions. | Available tools depend on installed extensions and platform. Tool permission modes and approval prompts apply. [AI Extensions](https://manual.raycast.com/ai/ai-extensions) |
| Screen Awareness | A user-triggered capture can attach the focused window's readable text, selection, focused control, app information, and screenshot. The attachment card reveals which sources were captured. | Requires permissions; readable content varies by app. Browser page content requires Browser Companion. The page states that passive selection reading does not modify the clipboard. [Screen Awareness](https://manual.raycast.com/ai/screen-awareness) |
| Agents | Save role/instructions, model, and available AI Extensions for an ongoing conversation; can have aliases and hotkeys. | The manual explicitly says Agents were called Presets in v1 and are functionally the same. The label alone is not evidence of a new autonomous execution mechanism. [Agents](https://manual.raycast.com/ai/agents) |
| MCP | Connect external tools and data through local stdio or remote HTTP servers, then use them in AI Chat, Quick AI, or AI Commands. | Requires connection/configuration and sometimes authentication; tools follow permission settings. [MCP](https://manual.raycast.com/ai/model-context-protocol) |
| Skills | Reusable local `SKILL.md` knowledge/instructions can be discovered or explicitly mentioned in AI Chat and Quick AI. | The manual specifically says AI Commands do not use Skills. [Skills](https://manual.raycast.com/ai/skills) |
| Automations | Run an AI prompt on a schedule and deliver each result to a new or existing AI Chat; runs may use AI Extensions, MCP, and Skills. | Local device must be awake with Raycast running for an on-time execution. Approval or a model question pauses a run. Missed occurrences fold into one later run; automations do not sync between devices. [Automations](https://manual.raycast.com/ai/automations) |

These AI capability pages are marked **Pro Exclusive** in the public manual. They establish supported product surfaces, not successful completion of arbitrary tasks. Natural-language action selection, reusable AI instructions, and importing selected content are therefore not empty competitive categories that Jotway can claim exclusively.

## Raycast: extensibility

Script Commands turn a local script into a searchable command, with a metadata header and optional hotkey. Users can add a script directory or create a script from a template; the manual describes calling personal workflows and internal APIs this way. [Script Commands](https://manual.raycast.com/script-commands)

The public API supports extensions built with TypeScript, React, and Node.js, supplies consistent UI components, and offers a Store distribution path. Extensions are therefore a developer surface and a user-facing installation surface. [Raycast API introduction](https://developers.raycast.com/), [Extensions](https://manual.raycast.com/extensions)

The API also exposes concrete output operations: copying content and pasting text or a file into the frontmost application's current selection. This matters for a complete input → operation → output workflow. [Clipboard API](https://developers.raycast.com/api-reference/clipboard)

Product interpretation: Jotway can evaluate a small number of configurable URL or local automation targets independently of deciding to build a general extension marketplace. The researched ecosystem does not prove that a marketplace is necessary for Jotway's scope.

## Raycast: frequent everyday utilities

| Utility | Verified behavior | Reference |
|---|---|---|
| File search | File and folder results appear in Root Search; a dedicated command adds metadata and recently used files. Name matching is the default, with an optional content-search setting. | [File Search](https://manual.raycast.com/file-search) |
| Calculator | Expressions can be entered in Root Search; documented categories include arithmetic, percentages, units, currencies, dates, and time zones. | [Calculator](https://manual.raycast.com/calculator) |
| Window management | Keyboard commands resize and position the focused window, move it between displays, and restore its prior size and position. | [Window Management](https://manual.raycast.com/window-management) |
| Clipboard history | Search and filter copied content; paste an entry into the active field, paste plain text, pin an entry, extract text from an image, or turn an entry into a snippet. | [Clipboard History](https://manual.raycast.com/clipboard-history) |
| Snippets | Save repeatable text, find and paste it, or assign a keyword that expands in another application's text field. Snippets can contain supported dynamic placeholders. | [Snippets](https://manual.raycast.com/snippets) |

Product interpretation: many useful operations share one entry point and keyboard convention, creating repeated reasons to invoke the launcher. This does not establish which utilities Jotway's users actually need, or justify implementing all of them.

## Alfred and LaunchBar: transferable interaction patterns

| Capability | Officially documented behavior | Relevance to Jotway (inference) |
|---|---|---|
| Alfred Universal Actions | Select text, a URL, or a file in another app, invoke the selection hotkey, and choose from actions relevant to that content type. Custom workflows can add actions. [Universal Actions](https://www.alfredapp.com/help/features/universal-actions/) | An explicit selected-text entry could reduce copying and pasting while preserving the current plain-text draft boundary. File support is a separate scope decision. |
| LaunchBar Instant Send | Send a selection from another app into LaunchBar, then choose an application, search template, script, or other target. [Instant Send](https://www.obdev.at/resources/launchbar/help/InstantSend.html) | A known destination should have a direct keyboard path without waiting for recognition. |
| LaunchBar abbreviation matching | Repeated choices adapt abbreviation ranking; users can also explicitly bind arbitrary abbreviations to items. [Abbreviation Search](https://www.obdev.at/resources/launchbar/help/AbbreviationSearch.html) | Fixed action shortcuts and explicit aliases can be evaluated independently of automatic learning. Jotway's local operation records currently do not train routing. |
| Alfred output to the source app | A workflow output can copy its result and optionally paste into the frontmost application. [Copy to Clipboard](https://www.alfredapp.com/help/workflows/outputs/copy-to-clipboard/) | Text processing could end with Copy or an explicitly chosen Replace Selection action, avoiding a separate trip through a chat application. |
| Alfred custom web searches | A user configures a keyword and URL template with a query placeholder. [Web Search](https://www.alfredapp.com/help/features/web-search/) | Configurable search/link actions could cover personal sites without shipping a dedicated integration for each site. |
| Workflows and interactive results | Alfred connects triggers, inputs, actions, and outputs; its Script Filter displays script-generated results. LaunchBar script actions may return items with titles and follow-up actions. [Alfred Workflows](https://www.alfredapp.com/help/workflows/), [Script Filter](https://www.alfredapp.com/help/workflows/inputs/script-filter/), [LaunchBar Features](https://www.obdev.at/products/launchbar/features.html) | Start by evaluating a small link-template or local-automation bridge. A general workflow editor or marketplace is a separate investment. |

## Jotway comparison snapshot

| Area | Existing repository behavior | Comparison boundary |
|---|---|---|
| Intent and explicit control | Plain-text draft routes through explicit selection, local matching, optional Jev recognition, and a default storage action. Application names can launch local apps. | Jotway already has a non-AI path and deterministic signals. Natural-language intent alone is insufficient as a competitive distinction. [Overview](../product/overview.md) |
| Target selection | A separate target selector and Option-Up/Down exist. An explicit target survives editing and panel reopening until submission, clearing, or Use Automatic. | Do not list basic target discovery or selection persistence as wholly missing. Per-action fixed global hotkeys and favorite ordering are a different capability. [Overview](../product/overview.md), [EditorView.swift](../../Sources/Features/Editor/EditorView.swift), [LauncherSession.swift](../../Sources/Features/Launcher/LauncherSession.swift) |
| Personal rules | Local Rules map a user-entered prefix to an enabled, ready action. The default action is still selected by module priority. | Rules are useful existing customization, but are not parameterized Quicklinks or a complete saved workflow. [Settings](../product/settings.md) |
| Reminder and calendar timing | Local interpretation reads the original draft independently of body rewriting. The panel shows destination and absolute time; unresolved time blocks submission. | Do not reuse the earlier claim that a parse failure silently becomes the current time. [Settings](../product/settings.md), [First use](../product/first-use.md) |
| Bringing in existing content | Copying text shortly before opening the panel can add it as quoted plain text; `consumeRecentPasteboardQuote` uses a one-second freshness window. | This is not persistent clipboard history, a dedicated selected-text command, or full frontmost-window capture. [PanelController.swift](../../Sources/Window/PanelController.swift) |
| AI output | Optional AI rewrites storage text. The ChatGPT action opens a new desktop conversation with the draft prefilled for the user to send. | This does not return a transformed answer to the source app or provide configurable AI Commands inside Jotway. [AI capability](../plugins/ai.md), [ChatGPT](../integrations/chatgpt.md) |
| Execution feedback and recovery | Failure restores text and route if newer work is safe; otherwise the failed submission is retained. Current first-use documentation says the retained submission has no recovery button. | The immediate submission receipt remains a **Work** proposal. Neither should be counted as complete based on a design document. [First use](../product/first-use.md), [Submission receipt](../product/submission-receipt.md) |
| Product scope | Five bundled actions cover Apple Notes, Reminders, Calendar, Chrome search, and ChatGPT. Drafts are plain text and memory-only; there is no browsable inbox or content history. | General file search, window management, snippets, a clipboard-history UI, and a public extension marketplace are scope expansions, not broken parts of the current contract. [Overview](../product/overview.md), [Architecture](architecture.md) |

The strongest comparison questions for later product validation are: how users choose a known target without re-evaluating suggestions; how existing content enters the draft; whether repeated operations can be saved with their settings; where the result goes; and how users know that an operation completed. These are research questions, not an approved roadmap.

Candidate product direction: make short capture and dispatch tasks dependable with few configuration steps, and measure that experience against competitors on the same examples. Natural-language input, Chinese support, or AI access alone does not establish an advantage. Supporting invocation from existing launchers could also be evaluated before attempting to replace their full utility sets.
