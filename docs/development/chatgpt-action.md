# ChatGPT action：打开新会话并带入草稿

> Role: **Work**
>
> 需求编号：`docs/development/chatgpt-action.md`
>
> 状态：接入方式已确认；公共架构已落地，本文已按当前接口核对。ChatGPT 专属模块尚未交接或实现。
>
> 公共模块、设置、选择和执行快照边界以当前 [Architecture](architecture.md#action-boundary-and-execution) 为准；本文只描述 ChatGPT 专属功能。

## 1. 场景与接入选择

用户在 Jotway 快速记录面板输入或粘贴文字，选择“交给 ChatGPT”，按 Enter 后进入官方桌面应用的新会话继续处理。

用户只有 ChatGPT Pro 账号，不配置 OpenAI API Key。本次选择使用：

```text
codex://new?prompt=<经过 URL 编码的文字>
```

官方文档说明，`prompt` 用于预填新建本地会话的输入框，不会自动发送。用户在目标应用确认后发送。[OpenAI 桌面深链文档](https://learn.chatgpt.com/docs/reference/commands#deep-links)

目标是支持该协议的官方桌面应用。账号、模型和最终发送由目标应用负责；不承诺创建 `chatgpt.com` 网页聊天、同步网页历史、继承网页项目或选择某个 Pro 模型。

## 2. 当前接入条件

Action 模块化已完成。当前代码可直接复用下列能力：

- 描述驱动的设置行、启用开关和可用状态。
- 没有 Jev Key 或建议时也可操作的手动目标选择。
- 显式选择优先、迟到建议保护和正确的反馈来源。
- 注册、准备缓存、配置版本、提交后任务接管与失败恢复。
- 统一安全错误和诊断。

| 当前实现 | ChatGPT 如何接入 |
|---|---|
| [ActionModule.swift](../../Sources/Actions/ActionModule.swift) | 实现 `descriptor`、`state`、`settings`、`onChange`、`refreshAvailability()` 与 `makeAction()` |
| [ChromeAction.swift](../../Sources/Actions/ChromeAction.swift) | 参考同文件内 `ChromeModule` 与 `ChromeAction` 的组织方式，复用外部应用打开模式 |
| [BundledActions.swift](../../Sources/Actions/BundledActions.swift) | 在 `BundledActions.modules(preferences:dependencies:)` 的列表加入 `ChatGPTModule()` |
| [ActionConfiguration.swift](../../Sources/App/ActionConfiguration.swift) | 根据模块的 `.userToggle(defaultEnabled: true)` 自动读写启用偏好，无需补专用配置字段 |
| [ActionSettingsView.swift](../../Sources/Actions/Settings/ActionSettingsView.swift) | 自动展示设置条目、分组、状态和开关，无需新增 ChatGPT 行 |
| [LauncherSession.swift](../../Sources/Features/Launcher/LauncherSession.swift) | registry 快照提供候选；显式 ID 独立于识别建议，无需新增 ChatGPT 选择逻辑 |
| [ActionExecutor.swift](../../Sources/Actions/ActionExecutor.swift) | 复用模块身份、配置版本和 registry revision 对应的准备结果，确认后接管执行 |
| [ActionFailure.swift](../../Sources/Support/ActionFailure.swift) | 使用统一的安全错误类型，不透传外部系统错误正文 |

本需求不修改 `SettingsView`、`AppState`、`LauncherSession` 或编辑区来识别 ChatGPT ID。当前也没有 ChatGPT 模块或注册项，仍需实施下文的专属逻辑。

当前工作区同时在接入中英文资源。唯一发现的公共展示缺口是 `ActionSettingsGroup.localizedTitle` 仍通过 `storage` / `search` ID 分支选择翻译；新“对话”分组的处理见 §3.2。该调整属于通用元数据补齐，不新增 ChatGPT 专属判断。

## 3. 模块声明与交互

| 项目 | 约定 |
|---|---|
| 稳定 ID | `chatgpt` |
| 目标行标题 | 交给 ChatGPT |
| 设置名称 | ChatGPT |
| 系统图标 | `bubble.left.and.bubble.right` |
| 展示色 | 复用现有 `.blue`，不增加专属颜色枚举 |
| 设置说明 | 打开新会话并带入文字，在 ChatGPT 中确认发送。 |
| 设置分组 | `id: "conversation"`、标题“对话”、顺序 `200`，通过通用分组元数据展示 |
| 启用 | 可关闭，缺省启用；沿用 `actionEnabled.chatgpt` |
| 可用性 | 定位到 `com.openai.codex`，且应用声明支持 `codex` scheme |
| 缺失状态 | 保留设置行并显示“未检测到兼容桌面应用，安装后可用”，退出可执行候选 |
| 兜底资格 | 无；`fallbackPriority = nil` |
| 模型参与 | `IntentHints.modelBinding = .none`，不进入 Jev 存入选项或搜索映射 |
| 专用配置 | 无目标位置、Key、模型、登录或 AI 改写设置；不需要专用详情页 |
| 窗口策略 | `.keepDestinationFrontmost` |

设置说明需要兼容该协议的 ChatGPT / Codex 桌面应用，不要求在 Jotway 登录或授予辅助功能权限。协议声明只能作为本地可用性条件，不能代替真实版本兼容性验收。

### 3.1 选择与触发

1. 使用现有 `⌥↑/⌥↓` 切换到“交给 ChatGPT”，然后 Enter 执行；候选行选择与快捷键使用同一状态。
2. 明确前缀：`问 ChatGPT `、`问ChatGPT `、`ChatGPT:`、`ChatGPT：`、`Codex:`、`Codex：`；英文忽略大小写。
3. 用户分流规则可指向 `chatgpt`。

前缀只决定去向，不修改正文。例如 `ChatGPT：解释这段代码` 会完整出现在目标输入框。仅输入“ChatGPT”或“Codex”时保留既有本地应用匹配语义，不增加裸应用名触发词。

普通问句不会因为本需求自动进入 ChatGPT。选择优先级、单个非默认候选、不可用目标提示与反馈规则全部沿用公共模块设计。

### 3.2 中英文展示

沿用现有 `ActionDescriptor` 的 `titleKey`、`settingsNameKey`、`summaryKey` 与 `L10n.text`。新增中英文资源，不在静态 descriptor 初始化时缓存已翻译字符串，也不按界面语言改变路由、草稿或配置身份。

| 资源 key（建议） | 中文 | 英文 |
|---|---|---|
| `action.chatgpt.title` | 交给 ChatGPT | Open in ChatGPT |
| `action.chatgpt.settings_name` | ChatGPT | ChatGPT |
| `action.chatgpt.summary` | 打开新会话并带入文字，在 ChatGPT 中确认发送。 | Open a new chat with your text, then send it in ChatGPT. |
| `action.chatgpt.missing` | 未检测到兼容桌面应用，安装后可用 | Install a compatible ChatGPT desktop app to use this action. |
| `action.chatgpt.opened` | 已打开 ChatGPT，请确认草稿后发送 | ChatGPT is open. Review your text and send it there. |
| `action.chatgpt.open_failed` | 无法打开 ChatGPT，请稍后重试 | Could not open ChatGPT. Try again later. |
| `action.chatgpt.invalid_text` | 无法生成完整深链，请检查文字后重试 | Could not create a link containing all your text. Check the text and try again. |
| `actions.group.conversation` | 对话 | Conversations |

分组翻译应使用与 descriptor 一致的可选 `titleKey` 声明，通用读取规则为“有 key 则解析，无 key 则使用原始标题”。如国际化任务尚未完成这项收口，在 `ActionSettingsGroup` 补一个兼容旧构造调用的可选 key，将现有存入/搜索分组的翻译 key 移回相应模块声明，再删除按分组 ID 的翻译分支。不要增加 `case "conversation"`。

这会涉及现有四个模块的分组声明，属于一次公共兼容调整；若派发时已有等价通用支持，直接使用，不重复修改。资源文件沿用 `Sources/Resources/en.lproj/Localizable.strings` 与 `Sources/Resources/zh-Hans.lproj/Localizable.strings`。

已有 `ChatGPT:` / `Codex:` 前缀可处理英文输入，中文前缀始终同时有效。沿用当前前缀匹配规则，不加入裸应用名，不借本需求增加泛问句识别。

## 4. 文字与深链处理

- 接收 `ActionInput.text`：沿用当前提交时去掉首尾空白的规则，保留正文内部的空格、缩进、空行、中文、emoji 与 Markdown 字符。
- 不进行 AI 改写，不额外剥离前缀，不接收图片或文件附件。
- 只设置一个 `prompt` 参数，不附加 `path`、`originUrl`、自动发送、模型或账号参数。
- 采用查询参数值编码。可参照现有 Chrome 实现的 unreserved 字符集，仅保留 ASCII 字母、数字及 `-._~`，其余 UTF-8 字节百分号编码；不能二次编码。
- `&`、`#`、`?`、`+`、`%`、引号等不能改变参数结构。解析后的 `prompt` 必须与提交正文完全相同。
- 不使用 shell 命令或剪贴板中转。
- 不静默截断长文。目标可接收的长度尚未实测；实施时确认可用范围。如需本地保护上限，明确为 Jotway 的限制，超限提示缩短并保留草稿，不套用 Chrome 的 2 MiB 搜索 URL 限制。

## 5. 准备与执行

新增一个 `Sources/Actions/ChatGPTAction.swift`，在其中放置 `ChatGPTModule`、`ChatGPTAction` 和私有 URL helper，沿用当前 Chrome 模块的文件组织。

`ChatGPTModule` 使用 `@MainActor @Observable`，`onChange` 使用 `@ObservationIgnored`。共享一份 `nonisolated static let moduleDescriptor`，执行实例使用相同描述。没有专用偏好时，状态使用 `configurationRevision: 0`、`hasSavedConfiguration: false`，`settings` 返回 `nil`；启用偏好和已保存配置判断由公共配置负责。

可用性根据本地检查结果保存在模块中，动态摘要在读取 `state` 时按当前语言生成。只有可用性发生实际变化才调用 `onChange`；语言切换不冒充执行配置变化。registry 的版本机制已能使可用性变化前的未提交准备失效。

1. `refreshAvailability()` 按 Bundle ID 定位应用并检查 scheme，使用轻量本地判断。
2. `makeAction()` 注入定位与打开依赖，创建配置已冻结的执行实例。
3. `prepare(_:)` 校验非空、编码正文并冻结 URL，保留 `actionID` 和 `inputIdentity`。准备可能由编辑或切换目标触发，不能打开应用。
4. `PreparedAction.execute` 在主线程重新定位应用并检查所需协议，处理准备后卸载或替换的情况，然后调用 `NSWorkspace`。
5. 指定应用 URL 打开，使用 `activates = true`、`createsNewApplicationInstance = false`、`allowsRunningApplicationSubstitution = false`、`promptsUserIfNeeded = false`；不交给任意注册 `codex://` 的 handler。
6. macOS 接受打开后返回“已打开 ChatGPT，请确认草稿后发送”。提示沿用 Launcher 展示时机，不为显示提示抢焦点。

定位和打开保持可注入，使用 ChatGPT 自身的构造参数或局部类型，不引用名为 `ChromeConnector.Open` 的业务类型。仅借鉴现有打开模式，不必新建通用深链框架。

模块构造器为定位、兼容性检查和打开提供真实默认实现，验证时直接注入替代依赖。虽然现有 `BundledActionDependencies` 还列出了四个内置 action 的专属依赖，本需求无需为 ChatGPT 向它追加 `chatgptLocate` / `chatgptOpen`；普通接入只增加一条 `ChatGPTModule()` 注册，隔离验证直接构造模块。

### 5.1 失败与成功的含义

空白输入、URL 构造失败、目标缺失或系统拒绝打开时返回安全错误，由通用提交管线恢复草稿；用户已经开始新草稿或正在组词时，通过 `FailedSubmission` 保留旧提交。

macOS 的成功回执只证明打开请求被受理，不能证明目标应用已正确预填或模型已受理。目标未登录、版本不兼容等不能通过这份回执可靠判断，不报告“已发送”，不自动重试发送或切换其他接入方式。

错误使用公共安全错误 Interface。运行日志不记录完整深链、正文或目标会话内容；既有本地意图反馈保留规则不变。

## 6. 专属修改范围

| 位置 | 修改 |
|---|---|
| `Sources/Actions/ChatGPTAction.swift` | 模块声明、兼容应用状态、准备与打开、依赖注入、安全错误 |
| `Sources/Actions/BundledActions.swift` | 注册 ChatGPT 模块 |
| 两套 `Localizable.strings` | 增加 ChatGPT 文案与对话分组标题 |
| `LauncherAction.swift` 及现有四个模块的分组声明（仅在通用翻译尚未收口时） | 按 §3.2 将分组翻译 key 归属模块，取消按分组 ID 的翻译分支；不添加 ChatGPT 条件判断 |
| 现有相关验证 | 使用注入点或临时最小用例验证，不自动新增测试文件或用例 |
| Current 文档 | 实现完成后记录真实功能与接入边界 |

不接入 OpenAI API、Workspace Agents、Codex CLI/app-server、快捷指令、网页 `?q=`、浏览器扩展或辅助功能自动点击；不在 Jotway 内展示回答、管理目标历史或登录状态。

## 7. 验收

| 场景 | 通过条件 |
|---|---|
| 扩展成本 | 专属运行时逻辑只在模块与注册项；本地化使用资源与通用字段，宿主中没有 ChatGPT 专属判断 |
| 新会话与预填 | 支持的桌面版本打开新会话，输入框文字与提交正文相同，没有自动发送 |
| 编码往返 | 中文、emoji、多行、空行、缩进及查询参数特殊字符往返一致，恰有一个 `prompt` |
| 长文 | 记录实测可用范围及本地保护规则，不能静默截断；打开失败仍保有全文 |
| 准备无副作用 | 输入、等待防抖和切换目标不打开应用，确认后才执行一次 |
| 无 Jev / 无默认 action | 不依赖模型即可通过前缀或手动选择执行；ChatGPT 不自动成为兜底 |
| 选择与状态 | 改选其他目标后不被前缀或迟到建议改回；关闭/缺失过滤和明确指定不可用目标的提示符合公共规则 |
| 设置 | 通用行正确显示名称、开关、安装状态；开关重启后保留，无多余配置页 |
| 中英文 | 标题、说明、状态、反馈和“对话”分组随界面语言更新；正文与前缀匹配不受语言切换影响，不触发重复准备或执行 |
| 执行错误 | 安全提示可见，原文恢复或保留为失败提交，不覆盖新草稿与中文组词 |
| 焦点 | 成功后目标应用保持前台，Jotway 不模拟输入或点击发送 |

实现阶段运行 `swift build` 和相关现有测试，用注入依赖验证 URL、指定应用、打开参数和错误分支。真实预填、长文兼容性及焦点默认人工验收；只有用户明确要求时才自动驱动 Jotway 或创建目标会话。

目前已核对官方协议，尚未真实验证目标会话的预填、长文和焦点行为。构建或 URL 编码成功不能替代这些验收。

本次接入复核已确认本机目标应用的 Bundle ID 为 `com.openai.codex`，并声明了 `codex` scheme；这只是安装元数据核对，不代表已完成实际预填验收。

## 8. 文档与交接

公共能力复用当前 [Action boundary and execution](architecture.md#action-boundary-and-execution)，不恢复已移除的 `/`、`、` 应用命令菜单，不重复实现公共选择和配置机制。

本轮只更新 Work 文档与索引。文档确认不触发交接；用户明确说“交接”时再按项目流程派发。

实现完成后新增 `docs/integrations/chatgpt.md`，同步设置说明及 `CONTEXT.md` 的内置 action 清单，将索引移到 Current actions 并删除本文。验证回执放在提交或交接记录中。
