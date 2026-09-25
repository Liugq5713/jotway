# ChatGPT action

> Role: **Current**

ChatGPT opens a new local desktop conversation with the submitted draft in the composer. The user reviews it and sends it in the destination application. Jotway does not require an OpenAI API key.

## Availability and settings

The action locates the official desktop application by bundle identifier `com.openai.codex` and checks its installed metadata for the `codex` URL scheme. The application name or installation path is not hard-coded. Declaring the scheme establishes local availability, not version compatibility or login status.

Settings show ChatGPT under **Conversations**, with an enable switch that defaults to on and persists as `actionEnabled.chatgpt`. Missing or incompatible installations remain visible in settings but are excluded from executable candidates. The action has no detail page, destination, model, login, or AI rewrite settings. Its labels and safe messages use the current English resource bundle.

## Routing

Select **Open in ChatGPT** using the candidate row or Option+Up/Down, or begin the draft with `问 ChatGPT `, `问ChatGPT `, `ChatGPT:`, `ChatGPT：`, `Codex:`, or `Codex：`. English matching is case-insensitive, and text may follow either colon immediately. Prefixes remain part of the submitted text. Saved phrase rules can also target the stable ID `chatgpt`.

Explicit selection takes precedence over prefixes and model suggestions. Bare `ChatGPT` or `Codex` names retain local application-matching behavior. Ordinary questions do not automatically select this action. ChatGPT is never a fallback and does not participate in Jev capture or web-search bindings; manual selection and prefixes work without a Jev key or configured storage action.

## Execution and text boundary

Preparation validates the submitted plain text and freezes `codex://new?prompt=<encoded-text>` without opening the application. The launcher trims outer whitespace at submission; the action preserves all remaining bytes, including prefixes, indentation, blank lines, Chinese, emoji, and Markdown characters.

There is exactly one query parameter, `prompt`. Only ASCII letters, digits, and `-._~` remain unescaped; the action checks that decoding reproduces the entire submitted text. It adds no workspace, account, model, or automatic-send parameter and uses neither a shell nor clipboard transfer. Jotway imposes no additional ChatGPT-specific text limit and never truncates the draft. The destination application's accepted long-text range is not established by URL construction; actual prefill and length compatibility require checking in the installed version.

On confirmation, the action re-locates and re-checks the application, then asks `NSWorkspace` to open the frozen URL with that specific application. It activates the destination, reuses the running instance, disallows application substitution, and suppresses system prompts. Success keeps the destination frontmost and reports that the text should be reviewed and sent there.

The [official desktop deep-link protocol](https://learn.chatgpt.com/docs/reference/commands#deep-links) defines `prompt` as composer prefill with manual send. macOS accepting the open request does not prove successful prefill, login, or model submission. The action does not promise a web conversation, web-history synchronization, project inheritance, or a particular model.

Empty text, URL construction failure, a missing/incompatible application, or a rejected open request returns a safe error through the shared failure-recovery flow. The original draft is restored, or retained as a failed submission when newer input or composition prevents immediate restoration. Runtime logs do not include the deep link, draft, or conversation content; the existing local intent-feedback policy still applies.
