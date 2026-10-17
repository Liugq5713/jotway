# notes-ai-assistance Specification

## Purpose

让用户存入 Apple Notes 的原文得到独立、可追溯的思考补充：回应其中的问题，综合相关历史，明确事实与建议的区别，并使空结果和失败可以诊断，同时保持原文存入的可靠性。

## Requirements

### Requirement: Question-aware assistance

启用 AI 补充时，系统 SHALL 允许回应草稿表达的问题；有足够信息提出具体分析时，SHALL 在 AI 补充中给出有增量的回答、建议或判断条件，而非仅重复历史摘要。普通记录无需强行转成问答，没有有用增量时 SHALL 允许空补充。

#### Scenario: Analyze remaining Jotway ideas
- **WHEN** 草稿为“jotway 当前还有什么好的想法没做”，候选中有 API 免配置、启动器匹配等具体想法及其问题背景，但没有完成记录
- **THEN** AI 补充至少提出一条结合这些背景的具体分析或建议，并说明完成状态仍待确认
- **AND** 补充不能只把相同功能清单再列一次，也不能声称已经检查代码或任务状态

#### Scenario: Ordinary capture without useful additions
- **WHEN** 草稿只是普通记录，且没有足够依据提供有用增量
- **THEN** 系统允许省略 AI 补充，不强制追问、不添加空泛建议或固定模板

### Requirement: Evidence and completion uncertainty

系统 SHALL 区分历史记载、基于资料的推断和新建议。旧笔记曾提出一项想法不构成当前仍未完成的证据；资料不足时 SHALL 明确状态未知。存在冲突时 SHALL 保留冲突，不能仅依据相似度、修改时间或检索缺失断言完成状态。

#### Scenario: Proposal without completion evidence
- **WHEN** 一篇旧笔记提出免配置 API，但检索资料没有后续完成或取消记录
- **THEN** 系统可把它作为候选方向或建议，不能称其为已确认未完成待办

#### Scenario: Conflicting historical records
- **WHEN** 提供的两篇来源分别写有同一方向的提议与后续完成记录，二者都有明确上下文
- **THEN** 分析综合两篇信息并说明记录中的变化，不将提议重新当作确定未完成事项
- **AND** 资料不能确立先后或存在矛盾时，明确标出需要确认

### Requirement: Separate bounded additions

系统 SHALL 完整保留草稿；按天归集时，原文指该主题按时间累计的全部原始条目。系统 SHALL 在原文之后共享呈现零至三条 AI 补充与零至五篇历史关联，AI 补充在前。每条采用的新增文字 SHALL 为单段、最多 240 字符及 960 UTF-8 字节。系统 SHALL 沿用现有补充解析器的容错行为：生成提示要求结果不超过 8192 UTF-8 字节，解析输入硬上限为 65,536 UTF-8 字节；可恢复的格式差异和额外元数据不导致有效条目被整份丢弃。空区块 SHALL 省略。不同条目 SHALL 提供不同信息，不重复原文或用同一历史摘要填充两个区块。

#### Scenario: Multiple useful additions
- **WHEN** 有效结果包含三条互补建议和两篇有依据的历史关联
- **THEN** HTML 与纯文字均呈现全部三条建议及两篇关联，原文仅完整出现一次，标题沿用草稿语言
- **AND** 新内容保持在原有生成区边界内，后续索引不把 AI 补充当作用户历史

#### Scenario: Bounded output rejection
- **WHEN** 可解析结果同时包含有效条目与无效、超长、重复或来源证据不合法的条目，或附带未知字段及标签元数据
- **THEN** 逐条跳过无效内容、忽略额外元数据，按原顺序保留至多三条有效洞察和五篇有效且不同的历史来源；坏条目不占用有效名额，不导致其他有效条目或另一个区块丢失
- **AND** 原文仍完整保留，未经校验的来源及元数据不进入正文

#### Scenario: Entire supplement is unusable
- **WHEN** 响应超过解析输入硬上限，或按现有容错规则处理后仍无可用内容
- **THEN** 本次不采用补充并保留真实诊断，破损结构化数据不作为原始 JSON 写入笔记；原文仍可保存
- **AND** 归集刷新沿用刷新失败规则，保留旧生成区的过期标记；有效空结果仍按空结果规则清除旧生成区

#### Scenario: Refresh shared additions after append
- **WHEN** 当天主题追加一条新想法且补充开启
- **THEN** 以该主题累计原文重新生成一份共享洞察与相关历史，采用时替换旧生成区，不把每轮结果追加成多个区块
- **AND** 新输入与历史资料中的不同观点保持可区分，旧生成文字不作为用户原始观点输入

#### Scenario: Refresh is empty or exceeds input budget
- **WHEN** 最新刷新合法返回空结果，或累计原文已超过完整生成输入预算
- **THEN** 前者移除旧生成区；后者保留全部原文并跳过刷新，有旧生成内容时标明只覆盖此前条目，不静默截断后声称分析了全部内容

### Requirement: Complementary historical attribution

有多篇不同来源提供实质性且互补的依据时，系统 SHALL 引导模型综合这些来源。每篇显示来源 SHALL 有原文中逐字存在的 8–160 字符证据，标题及链接由应用取自真实来源。同一篇来源 SHALL 最多显示一次；不得为了数量引入无关资料或拆分同一篇为多篇。

#### Scenario: Complementary sources are retained
- **WHEN** 两篇候选分别提供同一问题的不同具体约束，均可支持分析
- **THEN** 历史区保留两篇来源各自的关系说明和链接，AI 补充综合这些约束形成增量判断

#### Scenario: One source with several ideas
- **WHEN** 唯一相关来源包含五个方向，其余候选无关或重复
- **THEN** 历史区只呈现该篇一次；其内部有五个方向不被描述为检索到了五篇笔记

### Requirement: Optional preparation reliability

系统 SHALL 对普通逐条存入保留当前五分钟可选准备期限，覆盖检索、排队和生成。归集路径 SHALL 在分类后先保存原文，再以独立五分钟期限刷新生成内容；分类期限由归集规格定义。缺少配置、失败、无效输出或超时 SHALL 不阻止原文保存。一次确认 SHALL 最多创建一篇笔记或向一篇已有笔记追加一次原文；刷新仅能替换同一天同版本的生成内容。取消提交 SHALL 阻止尚未发出的原文写入，已保存原文不得因刷新取消而回滚。

#### Scenario: Deadline discards late output
- **WHEN** 检索或模型在五分钟内未结束，随后又返回有效结果
- **THEN** 普通存入继续保存原文；归集刷新保留已保存原文，迟到结果不能更新笔记或追加新笔记，终态诊断保持超时

#### Scenario: History unavailable but assistance available
- **WHEN** 检索出现普通网络失败，而生成服务能在剩余期限内完成
- **THEN** 系统可以仅基于草稿或主题累计原文生成补充，不声称已经找到或核实历史

#### Scenario: History invalidated before adoption
- **WHEN** 可选准备期间索引版本或历史配置被判定失效
- **THEN** 失效生成结果被丢弃；普通存入仍按冻结目标处理原文，目标失效则进入原有失败恢复；归集路径不回滚已经保存的原文，也不采用失效的历史关联

#### Scenario: Newer original revision wins
- **WHEN** 主题原文从版本 N 更新到 N+1，版本 N 的 AI 请求随后返回
- **THEN** 版本 N 的结果不写回；仅版本 N+1 且笔记仍为当天、内容和配置校验有效时才能更新生成区

#### Scenario: Refresh failure after successful save
- **WHEN** 原文已确认保存，而生成或生成区写入失败
- **THEN** 不报告原文保存失败，不恢复已保存草稿，不自动再次追加；保留旧生成内容时标明其覆盖截止条目，没有旧生成内容时不显示空洞察区

### Requirement: Preferences and action boundaries

系统 SHALL 保留已有 AI 开关、补充偏好和关闭状态，不启用旧改写偏好或自动标签。按天归集有独立开关，关闭补充不禁用用户已启用的 Flash 归类；关闭归集不改变补充偏好。首次标题生成及恢复 SHALL 独立于补充与归集开关，补充关闭不禁用标题请求；标题不授权生成洞察或历史检索。草稿里的问题只授权生成独立文字补充，SHALL NOT 改写原文、改变规则、发起联网检索或执行建议；历史片段中的指令 SHALL 只作为资料。

#### Scenario: Assistance disabled
- **WHEN** 用户关闭 AI 补充后确认存入
- **THEN** 不为本次存入调用历史检索或补充生成服务，仍完整保存原文；归集开启时可调用 Flash 判断当天归属，无论是否归集都可请求首次标题及恢复待补标题，但不得借此生成补充或检索

#### Scenario: Embedded instructions remain data
- **WHEN** 草稿、来源或补充偏好要求忽略输出规则、改写原文、泄露资料或执行外部操作
- **THEN** 系统只按固定的补充协议处理文字，没有额外执行、联网或原文替换

### Requirement: Content-free assistance diagnostics

系统 SHALL 为每次可选准备及最终采用记录可关联的诊断，包含检索数量、模型校验后的补充/历史数量、最终采用数量与明确结果码；零数量 SHALL 区分有效空结果、历史独有、格式拒绝、关闭、配置缺失、服务错误、超时和失效。终态 SHALL 只结算一次。日志 SHALL 不含草稿、查询、来源正文/标题/标识、原始响应或凭证，写日志失败不得阻断存入。

#### Scenario: Explain one history and no supplement
- **WHEN** 三篇有效候选被送入模型，模型合法返回一篇历史和空补充，最终写入采用该结果
- **THEN** 诊断能明确区分“送入三篇、模型选择一篇、补充为空、最终采用一篇”，而不是推断为只检索到一篇或服务未触发

#### Scenario: Distinguish parse failure from empty response
- **WHEN** 一次输出是合法空数组，另一次输出是格式不合法的 JSON
- **THEN** 两次均可保存原文，但分别留下有效空结果与格式拒绝的结果码，不能都记录成成功空结果

#### Scenario: Discard after successful generation
- **WHEN** 生成校验通过，但写入前来源边界记录保存失败，或最终组装剔除了内容
- **THEN** 诊断同时保留校验通过数量与实际采用数量，并解释丢弃原因，不把生成成功当作已写入成功

#### Scenario: Logging unavailable
- **WHEN** 日志存储不可用或队列丢弃事件
- **THEN** 原有日志不完整提示仍生效，存入不受阻；不能将缺少诊断事件解释为没有调用或成功完成

### Requirement: Streamed supplements are adopted only after completion

普通存入及按天归集刷新的 deep 补充 SHALL 使用流式请求，但接收的片段 SHALL 仅暂存在内存，不写入 Notes、草稿、正文日志或可恢复缓存。只有流完整成功、最终模型及现有补充解析和有效性检查通过后 SHALL 一次采用结果，继续逐条过滤无效补充。中断、截断、取消、超时或无效输出 SHALL 沿用 `Optional preparation reliability` 的原文保存及刷新失败规则；主备切换仅重新请求生成，不重复原文写入或分片更新生成区。合法空结果 SHALL 沿用既有空补充规则。

#### Scenario: Several fragments form one supplement
- **WHEN** 模型分多次返回补充内容，最终正常结束并通过完整校验
- **THEN** 片段接收期间不发出生成区写入，最终仅采用一份补充，原文仍完整且只保存一次

#### Scenario: Ordinary save loses the stream
- **WHEN** 普通逐条存入的补充在已有片段后断连，且没有可用备用或备用也失败
- **THEN** 丢弃部分补充，沿用原期限保存完整原文，不写入半份内容，不因流式失败再次创建笔记

#### Scenario: Grouped refresh switches provider
- **WHEN** 当天主题原文已确认保存，主模型已有片段后失败，备用返回完整有效补充
- **THEN** 仅依据备用完整结果及最新同日版本校验替换一次共享生成区；原文不重复追加，主模型片段不进入笔记

#### Scenario: Invalid or late refresh keeps saved originals
- **WHEN** 原文已确认保存，而生成流被取消、超过期限、明确截断、最终无效或已被新原文版本取代
- **THEN** 不采用片段、不回滚原文，也不恢复已保存草稿诱导重试；保留旧生成内容时继续显示其原有覆盖限制

#### Scenario: Valid empty output remains empty
- **WHEN** 流完整成功且最终校验得到合法空补充
- **THEN** 普通存入不添加空区块，归集刷新按既有规则清除旧生成区；结果不被误记为断连或格式失败
