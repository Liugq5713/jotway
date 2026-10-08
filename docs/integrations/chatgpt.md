# ChatGPT action

> Role: **Current**

ChatGPT opens a new local desktop conversation with the submitted draft in the composer. The user reviews it and sends it in the destination application. Jotway does not require an OpenAI API key.

## Availability and settings

The action locates the official desktop application by bundle identifier `com.openai.codex` and checks its installed metadata for the `codex` URL scheme. The application name or installation path is not hard-coded. Declaring the scheme establishes local availability, not version compatibility or login status.

Settings show ChatGPT under **Chats**, with an enable switch that defaults to on and persists as `actionEnabled.chatgpt`. Missing or incompatible installations remain visible in settings but are excluded from executable candidates. The action has no detail page, destination, model, login, or AI rewrite settings. Its labels and safe messages use the current English resource bundle.

## Routing

Select **Open in ChatGPT** using the candidate row or Option+Up/Down, or begin the draft with `问 ChatGPT `, `问ChatGPT `, `ChatGPT `, `ChatGPT:`, `ChatGPT：`, `Codex `, `Codex:`, or `Codex：`. English matching is case-insensitive. A name followed by a space and text, such as `chatgpt 帮我处理一下，如何能高效完成工作`, selects this action; text may also follow either colon immediately. Prefixes remain part of the submitted text. Saved phrase rules can also target the stable ID `chatgpt`.

With Jev configured, ordinary requests for an explanation, how-to answer, analysis, comparison, summary, translation, writing, or generated content can suggest ChatGPT without an application name or prefix. For example, `如何能高效完成工作`, `帮我分析这两种方案`, and `写一份计划` belong to the conversation category. Explicit web searches and requests for webpages, links, sources, or current public facts remain Chrome suggestions. Notes, reminders, and actual calendar scheduling remain storage routes; quoted, negated, or deferred assistant requests do not become conversation suggestions.

The module declares the `.conversation` model binding. A Jev conversation result maps to ChatGPT only when it is enabled and available in the current request snapshot. Missing, disabled, or incompatible installations cannot become a model target. ChatGPT is never a fallback and does not participate in storage capture.

Explicit selection takes precedence over prefixes and model suggestions. Bare `ChatGPT` or `Codex` names retain local application-matching behavior. Manual selection and prefixes work without a Jev key or configured storage action. A model suggestion still requires user confirmation to open the destination, where the user reviews and sends the text.

## Execution and text boundary

Preparation validates the submitted plain text and freezes `codex://new?prompt=<encoded-text>` without opening the application. The launcher trims outer whitespace at submission; the action preserves all remaining bytes, including prefixes, indentation, blank lines, Chinese, emoji, and Markdown characters.

There is exactly one query parameter, `prompt`. Only ASCII letters, digits, and `-._~` remain unescaped; the action checks that decoding reproduces the entire submitted text. It adds no workspace, account, model, or automatic-send parameter and uses neither a shell nor clipboard transfer. Jotway imposes no additional ChatGPT-specific text limit and never truncates the draft. The destination application's accepted long-text range is not established by URL construction; actual prefill and length compatibility require checking in the installed version.

On confirmation, the action re-locates and re-checks the application, then asks `NSWorkspace` to open the frozen URL with that specific application. It activates the destination, reuses the running instance, disallows application substitution, and suppresses system prompts. Success keeps the destination frontmost and reports that the text should be reviewed and sent there.

The [official desktop deep-link protocol](https://learn.chatgpt.com/docs/reference/commands#deep-links) defines `prompt` as composer prefill with manual send. macOS accepting the open request does not prove successful prefill, login, or model submission. The action does not promise a web conversation, web-history synchronization, project inheritance, or a particular model.

Empty text, URL construction failure, a missing/incompatible application, or a rejected open request returns a safe error through the shared failure-recovery flow. The original draft is restored, or retained as a failed submission when newer input or composition prevents immediate restoration. Runtime logs do not include the deep link, draft, or conversation content; the existing local intent-feedback policy still applies.
