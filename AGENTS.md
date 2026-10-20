# Repository Guidelines

## Context and Documentation

Before starting work, read [CONTEXT.md](CONTEXT.md) and use its terminology. For behavior changes, follow the relevant current specification from [docs/jotway.md](docs/jotway.md). Inspect `git status` and preserve existing uncommitted work.

Documentation has four roles: **Current** describes shipped behavior, **Work** describes one active change, **Reference** records reusable external or operational facts, and **Decision** explains a durable trade-off. Keep one role per document. Merge completed behavior into Current docs, then delete the Work document; Git preserves history. Verification logs belong in commits or task handoffs rather than Current docs.

OpenSpec 文档默认使用中文：新建或更新 proposal、design、specs、tasks 时，说明、任务、场景名称和提示词使用中文。保留工具要求的结构标题与标记（如 `MODIFIED Requirements`、`Requirement:`、`Scenario:`、`WHEN`、`THEN`、`SHALL`）、用于匹配现有规格的需求／场景名称（可另附中文说明）、代码标识和必要的外语示例；其余正文使用中文。修改后运行对应的 OpenSpec 校验。

## Change Workflow

在创建规划文档前，按风险和不确定性选择流程；不要只按文件数或用户描述的长短判断。先用一句话说明选择及原因。

- **轻量流程（默认）**：范围和预期行为清楚、局部且易回退，没有下述复杂因素。例如文案、局部样式、恢复既有规格行为的修复。会话中简述改动和验收方式后直接完成已授权工作，不创建 proposal/design/tasks、额外 Work 文档或交接文件。仅查阅相关代码与规格。
- **完整流程**：涉及数据迁移或删除、权限／隐私边界、外部写入的正确性（丢失／重复发送）、跨模块生命周期／并发协议、新架构／依赖，或仍有影响方案的重大歧义时，走 OpenSpec。design 仅在其条件适用时生成；复杂流程也按实际风险选择验证。
- **明确选择优先**：用户明确要求 OpenSpec、正式提案或指定已有 change 时遵循该流程；只要求讨论／计划时不实施。普通“帮我改／修复”不自动触发 propose。已有 change 保持原任务和验收约定，除非用户明确要求调整；轻量流程中发现复杂因素时说明原因并升级。
- **规格随实现更新**：轻量流程的新行为直接修改相关主规格和必要的 Current 文档；恢复既有行为的修复不改写正确的规格。只修相关条目，保留其他场景；术语变化才更新 CONTEXT.md。完整流程通过增量规格同步。阅读范围与改动范围一致，不为小改动遍历全部文档或历史。

## Project Structure

Jotway is a native macOS app using SwiftUI and AppKit.

- `Sources/App/`: application state, menus, settings, onboarding, and updates.
- `Sources/Actions/`: the action contract, registry, text pipeline, previews, and bundled actions.
- `Sources/Features/Editor/` and `Sources/Features/Launcher/`: editor/Markdown behavior plus launcher search and feedback mapping.
- `Sources/Window/`: quick panel presentation, focus, routing, and execution flow.
- `Sources/Data/`: GRDB schema plus application usage, intent feedback, and intent corrections.
- `Sources/Integrations/` and `Sources/Support/`: external APIs and macOS service adapters.
- `Sources/Plugins/`: optional AI providers and their registration.
- `Tests/JotwayTests/`: application tests; `Resources/`: metadata, icons, and entitlements.
- `Vendor/KeyboardShortcuts/`: locally patched dependency.

The inbox, records, cards, Summary, completion/export flow, and retired destination-specific subsystems have been removed. Jotway starts with its own database schema and storage locations; it does not import another application’s data or credentials. For plugin packaging or release scope, follow [the plugin distribution convention](docs/plugins/README.md#distribution).

## Build, Test, and Development Commands

Use Swift 6.2 with the macOS 26 SDK. The deployment target is macOS 15; SwiftPM is the normal development workflow.

- `swift build`: compile the application.
- `swift test`: run application tests.
- `./scripts/build-app.sh`: build, package, and ad-hoc sign `Jotway.app`; append `release` for a release build.
- `./scripts/build-app.sh --update`: build and replace the installed app directly, then restart and verify its process.
- `swift test --package-path Vendor/KeyboardShortcuts`: run dependency tests after changing vendored code.

For delivery, `./scripts/build-app.sh --update` replaces and restarts only an installation with the same bundle identifier. When the destination belongs to another application, keep it intact and report the conflict. Documentation, tests, and tooling changes do not require an app update.

## Coding Style

Use four-space indentation, `UpperCamelCase` types, and `lowerCamelCase` members. Name files after their primary type; preserve surrounding style in vendored files. Keep UI mutations on `@MainActor`. Prefer existing functions and types; introduce abstractions only for demonstrated reuse. No repository-wide formatter or linter is configured.

## Testing

按改动风险选择能回答实际问题的最小验证，不把所有检查叠成固定清单：

- 纯文档／流程修改：检查差异、链接及相关格式；修改规格时只严格校验受影响的 spec 或 change，不构建应用。
- 局部代码／样式修改：优先使用构建、类型检查或最相关的现有测试；行为修复需验证原问题，编译成功不能当作行为已通过。
- 涉及持久化、外部写入或并发：针对可能的数据丢失、重复执行、取消或过期结果验证相关路径。仅在新改动、失败或未解决风险需要时扩大检查；已有足够证据后停止。

Do not add tests unless the user explicitly asks. 临时脚本、模拟对象和无界面验证程序同样属于验证成本；只有现有检查无法回答具体风险问题时才编写，不把它们作为“不新增测试”的默认替代。Isolate persistence, clipboard, and preferences checks with in-memory repositories, unique pasteboards, and separate defaults suites.

完成时简述改动、已验证内容和未验证限制；通常在回复中交接。真实窗口／模型质量检查未执行时如实说明，不自动新增为交付门槛；用户明确要求的验收和已约定任务仍须完成，不能将未验证项标记为通过。

During verification, prefer `swift build` and non-UI checks; launch or drive `Jotway.app` only when the user requests UI verification. After code commits, follow the delivery rule below for app updates and restarts. For focus return, Chinese input composition, or other real-window behavior, describe manual verification unless the user explicitly requests automated UI verification.

## Commits and Pull Requests

完成改动并执行必要验证后，默认将当前工作区所有代码及配套文档、规格变更提交到本地 Git，无需再次询问；按主题拆分为聚焦的提交，并在最终回复中报告 commit hash 和验证结果。推送远端仍需用户明确要求。

应用代码提交成功后，默认立即运行 `./scripts/build-app.sh --update`，无需再次询问；按上文交付范围更新并重启已安装应用、验证进程，并在最终回复中报告更新结果，失败时说明原因。

Use short `<type>: <summary>` subjects (`feat:`, `fix:`, `chore:`) and keep commits focused. PRs should explain the problem, resulting behavior, validation, and remaining limitations. Keep generated build products untracked.
