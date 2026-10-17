# codex-task-execution Specification

## Purpose

定义 Jotway 向外部 Codex 提交任务时的执行参数合同，使用户能预期每个新任务请求的模型与推理强度，并明确参数不可用时的失败行为。未调整的配置、执行与恢复行为继续以 `docs/integrations/codex.md` 为准。

## Requirements

### Requirement: Explicit task model settings

Jotway Codex action SHALL 为每个新任务明确请求模型 `gpt-6-astra` 和推理强度 `high`，覆盖 Codex CLI 对这两个值的默认设置。所有进入该 action 的提交入口 SHALL 使用同一组固定值。用户 SHALL 通过目标菜单选择 Codex 后确认任务；`@codex` 不再指定目标或从任务正文中剥离。模板选择本身不得创建任务。

#### Scenario: Submit with different CLI defaults
- **WHEN** CLI 默认模型或推理强度为其他值，用户通过目标菜单选择 Codex 并确认非空任务
- **THEN** 创建会话时明确指定 `gpt-6-astra`，开始轮次时明确指定 `gpt-6-astra` 和 `high`

#### Scenario: Submit through the action menu
- **WHEN** 用户从菜单选择 Codex，编辑普通文字或模板展开正文后确认
- **THEN** 使用同一组固定参数；实际任务保留可见正文中的旧 `@codex` 字符，模板选择不算任务确认

### Requirement: Task settings remain locally scoped

Jotway SHALL 仅在新任务请求中应用固定参数，不改写用户全局 Codex 配置、不迁移已有会话、不增加模型设置项。浏览最近会话或读取会话名称 SHALL 不触发执行或更新模型参数。

#### Scenario: Read existing conversations
- **WHEN** 用户打开最近会话列表或进入一条已有会话
- **THEN** Jotway 不更改该会话的模型或推理强度，也不提交新的执行轮次

#### Scenario: Preserve global defaults
- **WHEN** Jotway 提交具有固定参数的新任务
- **THEN** 用户全局配置保持原值，其他 Codex 客户端仍可使用自己的配置

### Requirement: Rejected settings do not trigger fallback

指定模型或推理强度被 Codex 拒绝时，Jotway SHALL 沿用现有执行失败处理，不删除参数重试、不自动改用其他模型，也不报告完成。提交执行轮次前后的失败分类 SHALL 保持现有语义。

#### Scenario: Thread creation rejects the model
- **WHEN** Codex 在创建会话时拒绝指定模型
- **THEN** 本次尝试失败，不发送执行轮次，草稿沿现有失败恢复流程保留

#### Scenario: Turn request rejects settings
- **WHEN** 已发送执行轮次请求后 Codex 拒绝模型或推理强度
- **THEN** 沿用现有执行结果不确定的处理，保留可用的会话入口，不自动重试或标记成功

### Requirement: Explicit Codex selection exposes recent conversations

快捷输入中用户通过目标菜单选择 Codex 后 SHALL 可见原有五条最近任务区域，不依赖旧 @ 前缀；模板或目标菜单打开时临时让出相同下方区域，关闭后恢复。浏览、名称刷新和打开已有任务 SHALL 不提交草稿，不开始配置或新轮次。仅浏览或刷新保留未发送正文和目标；打开沿用现有合同，macOS 接受某个目的地后清空草稿和目标、隐藏列表，全部目的地打开失败则保留以便重试。

#### Scenario: Choose Codex and browse without submitting
- **WHEN** 用户选择 Codex，查看并点击一个已有最近任务
- **THEN** 沿用现有深链、保存结果或任务目录入口，不执行当前草稿；成功打开后清空草稿并隐藏列表，全部打开失败则保留正文、目标和列表；未打开任务时关闭模板或目标菜单会恢复最近任务区域

### Requirement: Codex execution depends on CLI availability

Jotway SHALL 以执行环境能否定位可执行的 Codex CLI 判断安装条件，不以桌面 App 是否安装、是否运行或仅有 helper 文件判断。只有当前检测确认 CLI 存在且执行 helper 就绪时，Codex action 才能执行。检测成功不保证登录、模型权限或所有 CLI 协议兼容性，后续失败沿用既有处理。

#### Scenario: Execution helper survives CLI removal
- **WHEN** 执行 helper 仍在，但重新检测确认找不到可执行的 Codex CLI
- **THEN** 显示“未检测到 Codex CLI”，不提供可执行的 Run with Codex 候选；设置页保留配置说明和重新检测入口

#### Scenario: CLI exists without desktop app
- **WHEN** 检测确认 CLI 存在且执行 helper 就绪，但未安装 Codex 桌面 App
- **THEN** Codex action 满足安装门禁，不因缺少桌面 App 被禁用；历史打开仍沿用现有结果文件或目录回退

### Requirement: Availability detection is bounded and read only

Jotway SHALL 在启动、展示快速记录面板、进入 Codex 设置及用户点击 Check Setup 时请求异步检测，合并并发请求。普通逐字输入不触发进程检测。检测过程中 SHALL 不创建或恢复会话、不开始执行轮次、不调用模型、不修改 Codex 配置或读取凭据。检测未完成或失败时 SHALL 不允许执行，且不把未知结果描述成 CLI 未安装。

#### Scenario: Repeated presentation while checking
- **WHEN** 一次检测未完成时连续触发面板展示或设置刷新
- **THEN** 合并请求且界面保持响应，显示检测中；检测最多等待三秒，超时显示检测失败并提供重试

#### Scenario: Late success after a newer failure
- **WHEN** 旧检测的成功结果晚于新检测的失败结果到达
- **THEN** 旧结果不能把 Codex 恢复为可用，也不能更改草稿或用户开关

### Requirement: Detection setup is explicit and preserves installed helpers

缺少或无法使用检测脚本时，Jotway SHALL 显示需要配置，并保留显式 Set Up Codex 入口；不得仅据此宣称 CLI 未安装或可用。用户运行配置时 SHALL 可先安装检测能力，即使 CLI 缺失；CLI 未安装或未登录时保留对应指引，不自动安装或登录。既有执行 helper 和不同内容的同名脚本 SHALL 不被静默替换，配置完成仍需再次确认才执行。

#### Scenario: First use without a detection script
- **WHEN** 用户从未配置 Codex，或旧安装只有执行 helper
- **THEN** 显示需要配置而非可执行；用户显式运行配置后可以获得 CLI 检测结果，取消配置保留草稿

#### Scenario: Setup runs before CLI installation
- **WHEN** 用户运行配置但当前没有 Codex CLI
- **THEN** 安装无冲突的检测脚本并提示先安装 CLI，不安装 CLI、不登录、不开始任务；回到 Jotway 后可检测并展示缺失状态

#### Scenario: Existing script differs from bundled resource
- **WHEN** 配置目标路径已有内容不同的脚本
- **THEN** 保留该文件并明确报告冲突，不把配置报告成完成

### Requirement: Availability changes preserve user intent and drafts

检测 SHALL 不改写 `actionEnabled.codex`。依赖恢复仅在用户偏好启用时恢复候选；CLI 缺失、检测中或失败时，已有显式 Codex 目标 SHALL 阻止新提交、显示原因并保留草稿，不改选其他 action。设置页和已保存的本地任务结果 SHALL 保持可访问；不可用期间不启动会话名称刷新连接，已有名称缓存保留。

#### Scenario: CLI becomes available again
- **WHEN** 用户安装 CLI 后重新检测成功，且执行 helper 就绪
- **THEN** 用户原来启用时恢复执行候选；原来主动关闭时保持关闭，不自动执行保留的草稿

#### Scenario: Selected target becomes unavailable
- **WHEN** 用户已选 Codex 并输入或展开模板，随后检测发现 CLI 缺失或检测失败
- **THEN** 保留正文和显式目标，阻止提交并显示原因，不转交 Notes；历史区域可保留缓存，但不启动名称刷新

### Requirement: Execution rechecks availability without automatic replay

每次 Codex 提交 SHALL 在启动任务进程前重新检测 CLI 与执行 helper；检测失败或依赖缺失不得发送执行请求，草稿沿既有失败恢复流程保留。复核期间更改草稿或目标 SHALL 使旧准备失效。只有尚未提交的新任务受门禁影响；可用性变化不得中止已开始任务、删除历史、自动重试或把提交后的不确定结果改为可安全重试。

#### Scenario: CLI disappears after display check
- **WHEN** 显示检测曾成功，但执行前复核已找不到 CLI
- **THEN** 不启动任务或创建会话，更新不可用原因，按既有失败恢复保留原文且不自动重试

#### Scenario: Draft changes during execution preflight
- **WHEN** 用户确认后、异步复核完成前修改正文或切换目标
- **THEN** 旧准备不执行到旧或新草稿，用户需再次确认当前输入

#### Scenario: Availability changes during an accepted task
- **WHEN** 任务已开始，另一检测报告 CLI 缺失或失败
- **THEN** 门禁只阻止新的执行；已有任务继续按其协议结果判断，提交后的失败仍保留既有不确定与禁止自动重试的语义
