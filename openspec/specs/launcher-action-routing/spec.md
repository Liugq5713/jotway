# launcher-action-routing Specification

## Purpose

定义 Jotway 保留的内置 action、本地应用建议和显式选择之间的边界，并规定移除 Jev 及退休 action 后旧入口的处理，保证草稿、已有数据和剩余执行流程仍可预测。

## Requirements

### Requirement: Bundled action surfaces reflect the supported set

系统 SHALL 保留 Apple Notes、Codex 和 Clipboard 三个内置 action 及各自适用的设置。底部目标菜单与键盘轮换的手动候选 SHALL 仅包含 Apple Notes 和 Codex，并沿用各自启用、配置和可用性规则；Clipboard 和本地应用 SHALL 不加入手动候选。Clipboard 的注册、采集、设置和已有数据 SHALL 保留，不新增替代历史入口。Personal Agent、Calendar、Reminders、Chrome 搜索和 ChatGPT 的专属菜单、配置、setup 和执行入口 SHALL 不再提供。

#### Scenario: Inspect action settings and target selection
- **WHEN** 用户打开 Apps 设置、输入非空草稿后打开目标菜单，或使用键盘轮换目标
- **THEN** 设置保留三个内置 action 的适用入口；手动目标候选仅可能出现 Notes 和 Codex，不包含 Clipboard 或本地应用；菜单保留 Let Jotway Choose，不出现已移除 action 或它们的授权与配置入口

#### Scenario: Removed actions were enabled before upgrade
- **WHEN** 旧设置保存了已删除 action 的启用状态、默认目标或配置
- **THEN** 这些值不能令旧 action 重新出现或被执行，剩余 action 的启用、配置和可用性不被覆盖

### Requirement: Routing does not redirect removed capabilities

系统 SHALL 按显式目标、剩余内置关键词、本地应用匹配、默认 action 的顺序解析目标，不包含模型分类。Notes SHALL 为唯一内置存入地板，不可用时提供既有 Set Up Notes 入口。移除的搜索/对话/日程目标 SHALL 不被自动替换为 Codex 或任何 Personal Agent 问答路径；旧 @ 名称作为普通正文保留。所有旧 action @ 前缀 SHALL 仅作字面正文，不指定目标或被剥离。

#### Scenario: Ordinary prose has a predictable destination
- **WHEN** 草稿为普通想法或问题，未显式指定目标，也未命中剩余内置关键词或合格应用匹配
- **THEN** 即时显示 Notes 或其既有配置入口，不等待模型；提问句式不触发 Codex、Notes 问答或网络分类，仍需确认才执行

#### Scenario: Submit a former reminder or search request
- **WHEN** 普通草稿为“提醒我明天买牛奶”或“Google 搜 Swift”，且没有其他有效显式选择或本地应用匹配
- **THEN** 目标按 Notes 地板或 Notes setup 解析，不创建提醒、不搜索网页、不调用 Codex 或 Notes 助手，执行仍需用户确认

#### Scenario: Type a removed mention
- **WHEN** 用户输入 `@personal 最近记了什么`、`@calendar 明天开会`、`@reminders 买牛奶`、`@reminder 买牛奶` 或 `@chrome Swift`
- **THEN** 旧前缀不指定目标、不被删除、不产生失效 setup；若用户确认存入 Notes，完整正文按 Notes 既有原文边界保存

#### Scenario: Bare application name still matches locally
- **WHEN** 用户输入已安装且可匹配的 Chrome、ChatGPT、Calendar 或 Reminders 应用名称
- **THEN** 仍可按既有本地应用匹配规则建议打开应用，不恢复对应 Jotway action，也不提交草稿给这些应用

### Requirement: Local application matching remains independent of Jev

系统 SHALL 保留 `application-matching` 的本机目录、匹配质量/使用记录/稳定身份排序、唯一应用候选和确认时复核契约。本地应用匹配 SHALL 不要求 Jev 凭据、防抖或模型结果；显式目标及剩余内置关键词优先，返回自动模式后使用当前草稿重新匹配。应用建议本身 SHALL 不启动应用，失败与过期回调不得覆盖新输入。

#### Scenario: Match and confirm without Jev
- **WHEN** Jev 已移除且网络离线，用户输入有合格本地匹配的应用名、拼音、缩写、有限误拼或既有打开命令
- **THEN** 按原排序同步提供最多一个应用候选，用户确认并通过复核后才打开；纯启动清稿、附带正文保留及成功使用计数沿用原契约

#### Scenario: An explicit action survives a new application match
- **WHEN** 用户显式选中 Notes 后，把草稿改为可匹配另一应用的名称
- **THEN** 保持 Notes 目标；选择 Let Jotway Choose 后才立即按当前草稿重新解析，不等待或请求模型

### Requirement: Draft routing performs no remote intent classification

系统 SHALL 不发起 Jev 请求、不生成 Jev 语义建议，也不得改用 fast、deep 或另一外部服务进行同类草稿目标分类。启动、输入、编辑、开关面板、返回自动模式及配置变化 SHALL 不恢复该路径；残留配置、历史记录或迟到结果 SHALL 不替换当前目标、改写草稿或触发执行。保留能力的显式问答、Notes 辅助与索引不属于目标分类。

#### Scenario: Old configuration cannot reactivate classification
- **WHEN** 用户保留旧 Jev 凭据和偏好，启动应用、输入草稿、重开面板或切回自动模式
- **THEN** 路由只按当前本地规则解析，不读取 Jev 密钥、不发送分类请求，不显示识别等待、密钥缺失或服务失败状态

#### Scenario: A stale model result cannot affect the current draft
- **WHEN** 历史模型建议或测试注入的迟到 Jev 结果到达，而当前已有本地或显式目标
- **THEN** 不采用其目标或正文，不执行 action，不覆盖当前选择或新草稿

### Requirement: Retained actions keep their execution boundaries

系统 SHALL 保留 Notes 原文存入、可选补充和失败恢复，Codex 的显式任务入口、配置与后台任务记录，以及 Clipboard 的查询和精确复制。Personal Agent SHALL 不再注册或执行；移除问答功能不得使普通问题自动执行 Codex 或启动其他 Notes 问答。

#### Scenario: Use retained explicit entries
- **WHEN** 用户通过目标菜单选择 Notes 或 Codex 入口
- **THEN** 各入口遵循其 Current 文档的配置与执行边界；菜单选择本身不执行，配置完成仍需再次确认；Clipboard 不作为手动候选出现，其既有本地能力与数据保持不变

#### Scenario: Preparation becomes obsolete or execution fails
- **WHEN** 用户在准备期间编辑草稿、切换目标或配置，或提交后执行失败
- **THEN** 旧准备不能执行到新草稿；执行失败按既有规则恢复原草稿或单独保留失败提交，不覆盖新输入

### Requirement: Ordinary footer confirmation is independent of schedule display

系统 SHALL 保留 22 pt 底栏、目标选择和普通准备失败提示。剩余 action 的确认 SHALL 不再等待时间摘要绘制或时间计划有效性，但仍执行可用性、草稿和配置有效性校验；空草稿、中文组词和临时便签规则保持不变。

#### Scenario: Confirm without a time preview
- **WHEN** 用户确认有效 Notes 或 Codex 输入
- **THEN** 不要求先显示日期或时间摘要，按相应准备与受理流程执行；失效或失败状态不被当作成功提交

#### Scenario: Empty draft composition and sticky mode
- **WHEN** 草稿为空、正在中文组词或处于临时便签模式
- **THEN** 目标入口和键盘分别遵循既有空草稿、输入法和便签边界，底栏不因删除时间摘要产生额外高度或改变普通输入布局

### Requirement: Feature removal preserves stored user data

升级 SHALL 不删除 Notes、Calendar、Reminders 中的用户内容，不清空 Notes 索引、Clipboard、Codex 任务记录、操作记录、模型凭据或既有 Personal Agent 调试文件。旧专属偏好可以保留为未使用数据，SHALL 不再参与当前路由、读取范围或配置有效性判断。

#### Scenario: Upgrade with existing personal data
- **WHEN** 用户从仍包含 Personal Agent 的版本升级
- **THEN** 原有内容与保留功能的偏好继续存在，无数据清空或全量索引重建，不请求已移除的系统权限
