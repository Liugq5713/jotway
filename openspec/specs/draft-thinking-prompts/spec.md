# draft-thinking-prompts Specification

## Purpose

让用户在快速记录面板中手动取得轻量思考提示，或主动开启停写后的自动追问，并在原编辑区继续表达。提示只在输入框下方临时展示，帮助本人补出依据、顾虑或比较标准，同时保持草稿、存入及本地数据边界。

## Requirements

### Requirement: Thinking prompts are explicitly requested from the footer

系统 SHALL 在快捷输入与临时便签的左下操作行提供一个 22 × 22 pt 思考提示按钮，位于模式入口、当前可用的单个最近文档入口及已有回顾入口之后、反馈与目标之前；最近文档入口不可用时不保留其位置。按钮 SHALL 沿用 `temporary-draft-mode` 的卡片悬停／键盘焦点显现规则，保留位置、不遮挡编辑区，提供本地化名称、提示与键盘激活。自动追问关闭时 SHALL 仅由用户激活按钮、换一个或重试来请求，不因输入、停留、切模式或展示面板自动请求；开启后的自动行为遵循本能力的停写规则。

#### Scenario: Request from either writing mode
- **WHEN** 用户在任一形态有非空普通草稿且处于可交互状态，激活思考提示按钮
- **THEN** 输入框下方打开提示面板并为本次完整草稿发起一次生成，正文和显式目标不变，不执行 action

#### Scenario: Protected writing states do not request generation
- **WHEN** 草稿为空白、中文组词中、模板菜单或填写会话活跃、首次引导或 action 配置中，或提交／应用启动尚未完成受理
- **THEN** 思考提示入口不可发起请求并提供简短原因，不中断当前工作，不强制提交组词

#### Scenario: Keyboard operation preserves editing semantics
- **WHEN** 用户通过原生焦点路径到达按钮并按 Return 或 Space
- **THEN** 只触发提示操作并返回原编辑区选区，不把按键同时当作草稿提交；模板及输入法既有键盘优先级保持

### Requirement: Automatic thinking prompts are opt-in and persistent

系统 SHALL 在 Writing Help 提供独立的“自动追问”开关，未保存偏好时默认关闭，并跨重启保留用户选择。开关 SHALL 说明开启后在停写约 1 秒时向当前 fast 模型发送草稿生成追问；设置页中切换不立即发送草稿。关闭 SHALL 立即取消自动计时、待处理候选及自动生成，使迟到自动回调失效，仍保留手动入口。该偏好 SHALL 不改变 Notes AI 补充、模型主备或草稿持久化策略，不保存提示内容。

#### Scenario: Start without a saved preference
- **WHEN** 首次使用或升级的用户没有保存自动追问偏好，即使 fast 可用或 Notes AI 补充已开启
- **THEN** 自动追问为关闭，输入与停写不发送提示请求；用户仍可手动请求一条提示

#### Scenario: Keep the selected preference after restart
- **WHEN** 用户开启自动追问后重启应用，或关闭后重启应用
- **THEN** 保留相应布尔选择；启动仍按既有规则显示空草稿，不恢复提示、计时或生成任务

#### Scenario: Disable while automatic work is pending
- **WHEN** 用户在自动计时、等待最新正文或自动生成期间关闭开关
- **THEN** 自动工作立即停止，旧结果不能显示或重新打开面板；手动入口仍可使用，正文与 Notes 补充偏好不变

### Requirement: Automatic requests follow settled draft changes

自动追问开启时，系统 SHALL 在可见可用的非空草稿每次实际正文变化并停写约 1 秒后生成或更新提示；连续输入重置计时，选区、窗口及重复刷新不触发。开启后返回编辑区、重新唤起或切形态 SHALL 为当前可用草稿重新评估一次，用户关闭抑制仍优先。自动工作 SHALL 遵循手动入口的保护条件，且不抢占最近文档或菜单；解除保护后仅为未处理的最新正文重新计时。同一资格范围的未变正文 SHALL 不因停留或结果完成反复请求。

#### Scenario: Debounce continuing edits in either mode
- **WHEN** 自动追问开启，用户在快捷输入或便签连续输入非空普通正文，再停止输入约 1 秒
- **THEN** 输入期间不逐字请求，停写后以最新完整正文生成一条提示；后续实际编辑再次触发相同规则，自动关闭时则不发生

#### Scenario: Resume after protected editing or viewing
- **WHEN** 用户正在组词、模板填写、查看最近文档或操作菜单，随后结束该状态
- **THEN** 期间不发起自动请求、不强制结束组词或驱逐当前区域；解除后为尚未处理的最新正文重新等待约 1 秒，组词结束无需再额外输入一个字符

#### Scenario: Close without reopening on the same text
- **WHEN** 自动追问开启，用户关闭提示或按 Esc 关闭，之后只等待、移动选区、切模式或隐藏再唤起
- **THEN** 该草稿正文未变时不自动重开；下一次正文实际变化并停写约 1 秒、手动请求或重新开启自动才解除关闭抑制

#### Scenario: No loop after an unsuccessful automatic attempt
- **WHEN** 当前正文的自动生成失败、超时、合法空结果、未配置或输入超限，且用户未改变正文或相关配置
- **THEN** 保留可理解的状态，不循环自动重试；正文变化、手动重试、重新开启自动或修复 fast 配置后才重新评估

### Requirement: One contextual scaffold leaves the thinking to the user

系统 SHALL 每次仅采用一条基于请求草稿的具体追问、待补依据或正反对照支架，延续草稿语言，不要求用户预先选类型。提示 SHALL 为单段纯文字，最多 240 字符及 960 UTF-8 字节，不代写答案、复述整份草稿、捏造背景或假称查阅历史和外部资料。无可用提示或校验不通过时 SHALL 显示明确空结果或失败状态，不用原始协议内容冒充提示。

#### Scenario: Ask about a concrete concern
- **WHEN** 草稿写明对一个决定犹豫，但没有说明最担心的后果
- **THEN** 提示可围绕该决定要求补充一个具体顾虑，不替用户断言其原因或作出决定

#### Scenario: Request evidence or a comparison
- **WHEN** 草稿中的判断缺少依据，或包含两个待比较的选项
- **THEN** 可分别提示补出一项依据或一个共同比较标准；一次只展示一种支架，不要求填写整张表

#### Scenario: Reject unusable output
- **WHEN** 服务返回超长、多条、非文字或不符合约定的结果
- **THEN** 本次提示不被采用，面板显示可重试状态，不展示原始 JSON、思考过程或部分未校验内容

### Requirement: The lower prompt panel stays separate and nonmodal

提示 SHALL 位于输入框下方的独立只读面板，标明 AI 生成及“基于生成时的草稿”，提供换一个与关闭。面板 SHALL 与最近文档详情、模板、目标菜单及 action 下方内容共用一个有界区域，不堆叠第二份下方内容；其最高 180 pt，受可用屏幕约束并可内部滚动。打开或返回结果 SHALL 不抢编辑焦点；自动关闭时，续写保留提示且不自动刷新；开启时，在新请求开始前保留上一条，停写规则满足后进入更新状态。关闭后 SHALL 恢复既有输入空间与几何策略。

#### Scenario: Continue writing with a visible prompt
- **WHEN** 自动追问关闭，提示已显示，用户在原编辑区增加或修改内容
- **THEN** 提示文字保持不变，不插入回答栏、不发起新请求；快捷输入与便签各自的 Enter 规则不变

#### Scenario: Replace another lower view
- **WHEN** 用户从最近文档详情或 Codex 最近任务区域手动打开提示
- **THEN** 只显示提示面板，最近文档读取被关闭并失效，原草稿及目标保持；关闭提示后按现有状态重新计算普通下方内容，不自动重开文档

#### Scenario: A menu or document takes precedence
- **WHEN** 提示显示或生成中，用户打开最近文档、目标菜单，或编辑触发模板菜单
- **THEN** 关闭提示并使本次生成失效，暂停自动请求，再展示请求的区域；旧响应不能覆盖它，解除保护后遵循停写规则重新评估

#### Scenario: Screen or manual geometry constrains the panel
- **WHEN** 用户在窄窗或屏幕边缘打开、关闭提示，期间手动移动或缩放窗口
- **THEN** 优先保留编辑与底部操作可达，下方区域收敛并内部滚动；关闭沿用最新手动选择及屏幕约束，不恢复过期窗口位置或撑大写作卡

### Requirement: Prompt content never becomes draft or save content

系统 SHALL 将提示、加载与错误状态保存在独立的临时界面状态中；手动或自动开启、生成、换一个和关闭 SHALL 不改变草稿正文、身份、正文版本、选区、撤销历史或显式目标。提示 SHALL 不自动进入任何 action 输入、存入原文、失败恢复或本地操作记录正文；用户自行写入的回答按普通草稿处理。已有 Notes AI 补充继续遵循 `notes-ai-assistance`，本能力不改变其开关或生成内容。

#### Scenario: Save after answering
- **WHEN** 用户阅读提示后在编辑区补写回答，再确认 Notes 存入
- **THEN** 本次 action 原文仅含编辑区正文，不附加面板里的问题、错误或标签；既有可选 Notes 补充仍独立适用

#### Scenario: Close or undo without text edits
- **WHEN** 用户只打开、换一个或关闭提示，没有修改正文
- **THEN** 不产生新的草稿版本或撤销步骤；已有正文编辑仍可按原顺序撤销

### Requirement: Snapshot requests have a bounded temporary lifetime

一次请求 SHALL 绑定触发时完整草稿快照、草稿身份、正文版本、面板会话、形态、模型配置、来源及唯一请求身份。普通续写 SHALL 不改写该快照；手动结果可对应原快照，自动结果只在正文仍匹配时采用，换一个使用最新正文。关闭提示、隐藏面板、切模式、受理提交、清空或外部替换草稿、进入配置／引导、模型配置失效及退出 SHALL 清理计时、候选、当前请求与提示。迟到结果 SHALL 不重新展示、覆盖新请求、改变几何或写入内容；后续新请求仅按当前偏好及关闭抑制重新评估。

#### Scenario: Finish a request while the user continues writing
- **WHEN** 自动追问关闭，手动请求等待期间同一草稿增加内容，且提示仍打开、会话与配置仍有效
- **THEN** 可展示基于生成时快照的结果，不覆盖新文字、不自动再请求；已展示提示也不随编辑变化

#### Scenario: Reject an outdated automatic result
- **WHEN** 自动请求尚未完成，用户已修改正文或进入受保护状态，随后旧请求成功或失败
- **THEN** 不把旧结果当作新正文的提示或失败状态；仍可用时仅为停写后的最新正文安排后续请求，不恢复被关闭或被其他区域替换的面板

#### Scenario: Refresh from the latest draft
- **WHEN** 用户在已有结果或失败状态下选择换一个或重试
- **THEN** 为最新完整草稿建立新的请求身份，旧结果不成为新草稿的一部分；旧回调不能覆盖本次状态

#### Scenario: Close or submit before completion
- **WHEN** 用户关闭提示、隐藏或切换形态、提交被受理，或清空／替换草稿后旧请求才返回
- **THEN** 丢弃旧结果，不重开旧提示、不恢复旧正文、不撤销提交，也不影响失败恢复；新会话是否生成仅由当前偏好、正文与保护规则决定

#### Scenario: Escape closes the prompt before hiding
- **WHEN** 提示打开且没有输入法或模板优先处理的状态，用户按 Esc
- **THEN** 先关闭提示并取消生成、保留草稿；再次按 Esc 沿既有规则收起快速记录面板

### Requirement: Generation uses independent bounded model work

提示 SHALL 使用现有 fast 配置与主备规则及独立执行流，不占用 Notes 标题或归类串行队列；每次逻辑请求自建立起包含内部排队的总期限最多 20 秒，到期结束等待并丢弃迟到输出。生成 SHALL 不占提交资格，编辑、目标选择及提交仍可用；同一时刻最多一个逻辑提示请求，重复激活不重复排队，加载时换一个不可用。失败、合法空结果与缺少配置 SHALL 可区分；新请求仅由手动操作或符合自动停写规则的候选启动。Notes 补充开关 SHALL 不限制或被提示操作修改。

#### Scenario: Slow provider does not hold the draft
- **WHEN** 提示请求持续无响应，用户继续写作或提交
- **THEN** 编辑与提交不等待提示；20 秒内结束本次等待，后续响应不能恢复已结束状态

#### Scenario: Missing configuration or repeated activation
- **WHEN** fast 未配置，或用户在本次生成中重复按按钮
- **THEN** 前者显示未配置并提供现有 Writing Help 配置入口、不发送请求；后者不增加模型调用或队列任务

#### Scenario: Coalesce edits while one request is running
- **WHEN** 自动追问开启，现请求尚未终结，正文先后变为多个新版本
- **THEN** 只保留最新待检查版本，不把各版本建成请求队列；现请求结束后，最新正文已停写约 1 秒且仍可用才建立下一请求及其 20 秒期限，否则继续等待

#### Scenario: Manual generation consumes an automatic candidate
- **WHEN** 同一正文已有自动计时或候选，用户先手动激活提示按钮、换一个或重试
- **THEN** 本次手动操作取代该候选，不紧接着为相同正文重复自动生成；后续实际编辑仍可触发自动更新

#### Scenario: Independent Notes preference
- **WHEN** Notes AI 补充已关闭，但 fast 可用，用户手动请求提示或已开启自动追问并停写
- **THEN** 可生成本次提示，不修改补充偏好、不触发 Notes 检索或存入

### Requirement: Only the requested draft crosses the model boundary

提示 SHALL 只发送本次草稿与固定生成规则，不自动读取最近文档、Notes 历史、浏览器、剪贴板载荷或 OCR。当前草稿属于显式 Clipboard 查询时 SHALL 不提供生成，切入该状态 SHALL 关闭并失效提示，保持 `clipboard-history` 的本地边界。超出完整输入预算 SHALL 明确拒绝，不静默截断。运行诊断 SHALL 只记录请求身份、模型、数量、耗时与结果码，不含草稿、提示、原始响应或凭据；不创建内容归档或持久化提示历史。

#### Scenario: A recent document is visible
- **WHEN** 最近文档详情打开，用户请求草稿提示
- **THEN** 只将编辑区草稿作为内容发送，详情、文档标识与历史索引不成为上下文，不额外申请 Notes 权限

#### Scenario: Clipboard input remains local
- **WHEN** 当前为 Clipboard 查询，或提示请求期间切入该状态
- **THEN** 不为该查询发送提示请求，并取消未完成工作；历史正文、图片及 OCR 不进入模型或提示诊断

#### Scenario: Large input or embedded instructions
- **WHEN** 草稿超过完整输入预算，或包含要求改写、联网、执行及泄露资料的指令
- **THEN** 超预算时不请求并保留全文；其余情况仅按固定提示规则处理资料，不执行额外操作或改写正文
