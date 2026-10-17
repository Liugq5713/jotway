# notes-daily-grouping Specification

## Purpose

让用户随手提交的想法在指定 Notes 文件夹内按当天项目或自然主题持续积累，保留每条原文和记录时间，并严格区分可更新的当天笔记与只读历史资料，减少手工分类和重复整理。

## Requirements

### Requirement: Daily writable scope

系统 SHALL 仅将当前 Notes 存入文件夹内、当前本地自然日创建且由归集功能管理的笔记作为追加目标。历史检索 SHALL 沿用既有授权范围，与写入范围独立；昨天及更早笔记仅可读取。系统 SHALL 不批量合并、搬迁或删除旧笔记，不因旧笔记今天被修改而使其可写。

#### Scenario: Same project on different days
- **WHEN** 昨天已有 Jotway 项目笔记，今天首次提交该项目想法
- **THEN** 在当前存入文件夹创建今天的项目笔记，昨天的笔记保持原样，并可作为相关历史来源

#### Scenario: Matching note outside writable scope
- **WHEN** 相关笔记位于其他文件夹、早于今天创建或尚未由归集功能管理
- **THEN** 不向它追加，不重命名或接管它；仅在既有历史读取权限内作为参考

#### Scenario: Midnight or time zone changes
- **WHEN** 提交排队期间进入下一本地自然日，或时区变化使原候选不再属于当天
- **THEN** 写入前重新判断当日范围，在当前日重新选择目标；保留原始提交时间，不写入已成为往日的笔记
- **AND** 已保存笔记的迟到 AI 结果跨日后不得再写回

### Requirement: Project-first semantic grouping

系统 SHALL 使用已配置的 fast 主备模型链，默认优先 `deepseek-flash`、符合切换条件时尝试 `kimi-k2.7-code-highspeed`，依据新想法和当天候选的完整原文，按用户工作或研究主题宽松归集。有合理、具体且有用的共同主题且能选择合适候选时 SHALL 优先追加，不要求完全相同的目标、措辞或粒度；简短描述、父子主题、相关子方向及不同仓库、工具、产品 SHALL 不单独导致拆分。项目 SHALL 指用户工作而非资料身份；同一工作下不同功能、故障、建议或反对意见 SHALL 允许归入同一篇。没有命名项目时 SHALL 支持自然主题。用户明确区分的不同工作 SHALL 保持独立；生成区内容、仅有泛化技术词重合或提交时间接近 SHALL 不单独构成归类依据，不得虚构共同目标。

#### Scenario: Different concerns in one project
- **WHEN** 当天已有 Jotway 记录体验想法，新输入为“Jotway 的启动快捷键偶尔失效”
- **THEN** 在候选完整可用且无写入冲突时，归入同一篇当天 Jotway 项目笔记

#### Scenario: Different projects and opposing views
- **WHEN** 输入明确属于另一用户工作项目，或输入反对当前项目笔记中的方案
- **THEN** 前者不因共享技术关键词而合并，后者仍可追加到当前项目，保留不同观点

#### Scenario: Natural topic without a named project
- **WHEN** 两条想法均明确涉及英语听力练习，但没有项目名
- **THEN** 可归入当天同一自然主题，无需用户预先创建分类

#### Scenario: Different repositories for one research topic
- **WHEN** 当天唯一相关合法候选原文为 `https://github.com/tester-army/e2e` 加“agent 自动化测试”，新原文为 `https://github.com/browserbase/stagehand` 加“自动化测试”，且两条均未声明不同工作目标
- **THEN** 将新原文追加到该自动化测试主题，不因仓库名称不同而独立保存
- **AND** 交换上述两条的提交顺序时，仍选择追加；保留候选已有标题及每条完整原文与提交时间

#### Scenario: Multiple references with a shared goal
- **WHEN** 当天已有浏览器自动化测试工具调研主题，新原文在同一工具选型目标下同时比较两个仓库或产品
- **THEN** 归入该候选，不因提及多个外部项目而触发多项目独立保存

#### Scenario: Shared technology in distinct user work
- **WHEN** 当天候选是“为订单系统补充自动化测试”，新原文明确是“为招聘系统补充自动化测试”，未表达共同调研或比较目标
- **THEN** 独立保存新原文，不仅因“自动化测试”重合而合并不同工作

#### Scenario: Broader topic includes related subtopics
- **WHEN** 当天唯一相关合法候选包含“浏览器自动化测试”，新原文为“研究 Agent 自动化测试的用例生成”，均未限定不同用户工作
- **THEN** 按共同的自动化测试研究主题追加，不要求两条涉及完全相同的测试层级或方法
- **AND** 交换两条顺序仍追加，保留已有标题及每条原文，不因标题较窄而拆分

#### Scenario: Brief capture without an explicit shared goal
- **WHEN** 当天有自动化测试工具调研候选，新原文为一个工具链接加“浏览器测试”，没有写明“用于同一调研”
- **THEN** 根据短描述与候选原文的合理主题关联追加，不要求用户补全共同目的

#### Scenario: Unrelated content with a generic umbrella
- **WHEN** 当天候选是自动化测试，新原文为学习 Swift 内存管理，未表达测试或共同工作关系
- **THEN** 独立保存，不仅因两者都属于“技术学习”而合并

### Requirement: Conservative grouping fallback

系统 SHALL 只采用本轮合法候选。缺乏合理共同主题、存在明确工作边界、多个候选依据原文仍无法合理区分、多个无关主题没有共同主线、无候选、预算不足、缺少主配置、主备链终态服务失败、返回模型不符或无效输出 SHALL 降级为独立保存。仅因描述简短、主题粒度不同或不能完全确认细节 SHALL 不触发新建；多个相关候选存在时 SHALL 选择原文支持最充分者，真正无法取舍时独立保存。归类等待 SHALL 遵循 Independent grouping deadlines，不再使用包含候选准备的十五秒期限；不弹分类问题、不拆分改写原文，不凭自报概率强制归类。备用只重试只读分类请求，不重试 Notes 写入；主备共同占用原有 120 秒分类期限，不重置候选准备或 300 秒决策预算。独立保存 SHALL 按 notes-initial-titles 取得 AI 标题或临时标题，不采用本地正文截取；原文保存后的迟到归类结果不得再改变归属。

#### Scenario: Ambiguous short input
- **WHEN** “只处理当天的”同时可能指向日程项目和笔记项目，原文没有足够证据
- **THEN** 独立保存该原文，不仅凭最近使用主题选择目标

#### Scenario: Unavailable or invalid classifier
- **WHEN** 配置的主备链均失败或到期、返回其他模型、未知目标标识或无法解析的结果
- **THEN** 原文仍独立保存；迟到归类结果不得移动或重复追加已经保存的内容

#### Scenario: Multi-project original
- **WHEN** 一次提交同时讨论两个不同用户工作项目，没有共同工作或研究主线，也没有明确主要归属
- **THEN** 整条独立保存，不分拆、不复制到多篇笔记

#### Scenario: Multiple plausible research candidates
- **WHEN** 当天分别已有订单系统和招聘系统的自动化测试主题，新原文仅为一个未标明用途的仓库链接加“自动化测试”，无法判断具体归属
- **THEN** 独立保存，不凭最近提交时间或强行扩大主题来选中任意候选

#### Scenario: Prefer the better supported candidate
- **WHEN** 当天有“自动化测试工具调研”和“Agent 记忆架构”两个合法候选，新原文为“Agent 自动化测试用例生成”
- **THEN** 追加到自动化测试候选，不因两个候选均有词汇关联就新建，也不凭最近使用时间选择

#### Scenario: Fallback classification succeeds
- **WHEN** 主分类请求断连，备用在剩余分类期限内返回合法的当前候选决策
- **THEN** 采用该决策前重新执行当前日期、目标及版本校验；只有一次原文保存，不重新准备或更改候选身份

#### Scenario: Late classification cannot duplicate a save
- **WHEN** 主尝试已结束，备用分类完成并已保存原文，随后主请求才返回
- **THEN** 丢弃迟到决策，不追加第二次、不新建副本，不重复发出保存完成反馈

### Requirement: Chronological original entries

系统 SHALL 记录每次提交的稳定身份、提交时间及顺序，在目标笔记中按提交顺序追加完整原文。主题名称、日期、时间标记与原文 SHALL 可区分。不同提交中相同文字 SHALL 保留为不同条目；同一提交的恢复不得再次追加。除既有路由前缀移除和换行规范化外，原文保护沿用 Current Notes 规则。

#### Scenario: Whitespace and intentional repetition
- **WHEN** 两次不同提交包含相同句子、空白、代码或标题样文字
- **THEN** 两个条目各自保留全文和时间，不把表达重复误当作重试，也不删改缩进或空行

#### Scenario: Concurrent arrivals
- **WHEN** 同一天连续提交两个同项目想法，分类或生成响应乱序返回
- **THEN** 归类采用最新已保存候选，原文仍按提交顺序出现且各一次，不相互覆盖

### Requirement: Protected note updates

系统 SHALL 在修改前核实笔记身份、文件夹、日期、可读写状态和完整内容版本。已检测到的手动编辑、移动、删除、附件、共享或锁定状态 SHALL 阻止自动覆盖。原文写入确认与 AI 刷新结果 SHALL 分开报告；更新结果不明时不得当作明确失败自动重写或新建副本。缓存及修改时间 SHALL 仅辅助候选准备，不替代实际更新前的完整正文校验；减少重复读取 SHALL 保留最后一次完整写前校验及必要写后回读。

#### Scenario: User edits a managed note
- **WHEN** 写入前发现用户已修改候选笔记，完整内容与受管理版本不符
- **THEN** 保留用户修改；新想法独立保存，停止对冲突笔记的 AI 刷新，不尝试根据标题重建并覆盖它

#### Scenario: Destination changed
- **WHEN** 用户改变存入文件夹，尚未执行的写入仍指向旧配置
- **THEN** 使该写入失效并沿用草稿失败恢复，不悄悄向旧文件夹或新文件夹写入

#### Scenario: Write result uncertain
- **WHEN** 请求已经发出但没有可靠的成功或失败确认
- **THEN** 通过提交身份和实际正文核对结果；无法核实则报告保存状态不明，不盲目重试，不触发 AI 刷新

#### Scenario: Cached state misses an external edit
- **WHEN** 候选轻量检查未发现变化，但选中目标的最终检查发现正文不同、附件或其他不可写状态
- **THEN** 不覆盖该笔记，使对应缓存失效，并沿用已有冲突或失败恢复规则

### Requirement: Independent grouping controls

系统 SHALL 在 Notes 设置提供独立的按天自动归集开关，未设置时默认开启并保留显式关闭。归类 SHALL 复用全局 fast 主备配置而不要求启用 Personal Agent 或历史索引。AI 补充关闭 SHALL 禁止洞察生成及其历史检索，但不改变归集开关；归集关闭 SHALL 保留逐条新建方式，但首次标题生成与待补恢复 SHALL 独立运行，不受归集、补充或历史索引开关控制；设置 SHALL 明确该范围。

#### Scenario: Group with assistance disabled
- **WHEN** 自动归集开启、fast 主模型已配置，但 AI 补充关闭且历史索引不可用
- **THEN** 仍可使用配置的 fast 模型链将当天同项目的原文追加在一起，不调用补充生成或历史检索

#### Scenario: Grouping disabled or key missing
- **WHEN** 用户关闭归集，或开启后 fast 主模型配置缺失
- **THEN** 前者不调用分类模型并使用原有存入流程；后者显示配置状态并独立保存原文，不要求用户先完成 Personal Agent 设置

#### Scenario: Primary works without fallback
- **WHEN** fast 主模型已就绪而备用未配置或设为 None
- **THEN** 归集仍可使用主模型；设置区分主可用与备用不可用，并提供全局主备配置入口，不把密钥固定写入 DeepSeek

### Requirement: Restart and completion semantics

系统 SHALL 在重启后识别当天已确认的受管理笔记与提交，避免重复追加。原文保存成功 SHALL 以 Notes 的确认及必要回读为依据，只产生一次保存完成反馈；生成内容更新失败不得恢复已保存草稿并诱导重复提交。重启后的刷新仅能恢复当天、内容版本仍匹配且配置有效的工作。

#### Scenario: Restart after original save
- **WHEN** 原文已保存，AI 刷新尚未完成时应用退出并在当天重启
- **THEN** 原文不重复追加，可从已保存主题的最新原文恢复一次刷新，不恢复旧生成响应

#### Scenario: Restart on a later day
- **WHEN** 昨天保存成功但 AI 刷新未完成，今天重启
- **THEN** 不修改昨天笔记，不为旧刷新创建今天的副本；今天新输入进入今天的主题

### Requirement: Natural-day candidate cache

系统 SHALL 在内存中按存入文件夹、本地自然日及时区隔离当天受管理笔记的已确认完整原文与版本，仅在读取验证或写入确认后更新。缓存 SHALL 有容量上限，不新增正文落盘，不依赖历史索引或 AI 补充开关。跨日、范围改变或归集关闭 SHALL 清理不再适用的缓存；退出后清空，重启按需恢复。缓存淘汰 SHALL 不等于排除合法候选，不得截断原文或只按标题分类。

#### Scenario: Warm same-day captures
- **WHEN** 当天连续提交，候选缓存完整且本轮轻量检查未发现状态变化
- **THEN** 分类复用已确认的完整原文，不重新读取这些候选的正文或 HTML
- **AND** 新提交保存确认后更新缓存，下一次分类可见最新条目，AI 生成区不作为原文

#### Scenario: Midnight and scope changes
- **WHEN** 本地时间从 10 月 13 日跨入 10 月 14 日，或存入文件夹、时区发生变化
- **THEN** 下一次候选准备使用新范围并释放旧范围缓存，不以缓存建立后 24 小时作为到期规则
- **AND** 旧范围异步结果不能重新填入当前缓存或授权写入，昨天笔记仍只读

#### Scenario: Restart or memory eviction
- **WHEN** 同一天重启、缓存条目被淘汰或单篇内容超过缓存容量
- **THEN** 按需从 Notes 验证恢复完整原文用于本轮分类；无需持久缓存也能完成归集
- **AND** 单篇过大时不强制保留在缓存，候选集合与既有模型输入预算规则保持一致

#### Scenario: Confirmed revisions only
- **WHEN** 原文追加或 AI 刷新已确认成功，或旧版本的异步结果迟到
- **THEN** 前者更新同篇缓存的完整已确认版本；后者不能覆盖新版本，失败或结果不明的写入不进入已确认缓存

### Requirement: Reduced candidate reads

系统 SHALL 先依据本地管理记录限定当日存入范围，再对缓存命中的候选执行不含正文、HTML 或附件枚举的轻量检查；缺失或状态变化的候选 SHALL 完整验证后使用。不得为归集扫描无关文件夹或往日笔记正文。确认不合法的候选 SHALL 排除并失效缓存；临时读取失败 SHALL 不永久标记为用户编辑冲突，无法完整准备时明确降级，不静默漏掉未知候选后继续正常分类。

#### Scenario: Changed or unavailable candidate
- **WHEN** 本轮检查发现候选被移动、删除、锁定、共享或修改，或检查暂时失败
- **THEN** 不直接复用其旧缓存；可读取的变化通过完整验证决定是否仍合法，实际冲突保持原笔记不变
- **AND** 网络、Notes 服务或权限暂时失败不永久封禁这篇笔记；后续恢复后可重新验证

#### Scenario: Selected-target validation
- **WHEN** 模型从多个候选中选择一篇追加
- **THEN** 只对该目标执行一次最终完整写前校验，不再在上层重复同样的完整预读；仍保留写后身份、文件夹及完整正文确认

#### Scenario: Fewer reads without batch support
- **WHEN** 四篇未变化候选均已缓存，而系统无法使用批量属性读取
- **THEN** 分类准备仍不读取四篇正文、HTML、标题和附件列表，逐项轻量读取次数低于原路径的约 44 次
- **AND** 回退采用同一候选集合与保护规则，不转为扫描整个文件夹

### Requirement: Independent grouping deadlines

系统 SHALL 为每次提交设置包含归集排队、候选准备和分类的 300 秒决策预算，为分类保留 120 秒；候选准备及此前排队最多使用 180 秒。分类 SHALL 在候选准备完成后开始独立的 120 秒期限，包含模型排队，不再因前置十余秒耗时提前放弃。跨日重选 SHALL 共用本次总预算。预算不包含后续原文写入确认；保存后 AI 补充继续使用独立的 300 秒期限。到期 SHALL 丢弃迟到结果，保持写入顺序与一次提交最多一次原文保存。无可用标题的新建 SHALL 使用首次标题规格定义的独立有限预算，不重新启动分类或延长已结束的归类决策。

#### Scenario: Slow preparation still allows classification
- **WHEN** 候选准备耗时 20 秒，模型随后耗时 30 秒返回合法追加决策
- **THEN** 在配置、日期和目标检查仍有效时正常追加，不因超过原十五秒期限新建

#### Scenario: Preparation consumes its available budget
- **WHEN** 包含排队的候选准备未能在 180 秒内完整完成
- **THEN** 取消本轮归类准备并记录准备超时，不发起只剩零碎时间的分类请求；原文按既有顺序进入独立保存
- **AND** 晚到的读取不能更新缓存、改变终态或触发额外写入

#### Scenario: Model deadline and late response
- **WHEN** 候选及时准备完成，但模型在其独立 120 秒期限内未返回，随后才完成
- **THEN** 仅采用一次超时降级，迟到结果不能追加、搬移笔记或恢复已保存草稿

#### Scenario: Pending external write blocks safe progress
- **WHEN** 归类预算已结束，但前序 Notes 写入仍在确认中或同一提交存在未核实写入
- **THEN** 归类终态确定，原文写入仍遵守串行与不确定结果恢复规则，不为满足时限越过前序写入或创建副本

### Requirement: Content-free grouping diagnostics

系统 SHALL 为同一提交关联记录排队、候选准备、分类、最终校验与回读耗时，候选数量、缓存命中与未命中、实际 Notes 读取调用次数，以及模型 append/new 决策、最终追加或新建结果和明确降级原因。每次归类终态 SHALL 只结算一次。日志 SHALL 不含笔记正文、标题、Notes 标识、原始模型响应或凭证；日志缺失或写入失败不阻断保存。

#### Scenario: Explain independent saves
- **WHEN** 一次模型正常选择新建，另一次候选准备超时，另一次选中后遇到写入冲突
- **THEN** 诊断分别说明语义新建、准备超时和选中后冲突，不以同一 success 结果掩盖差异

#### Scenario: Compare cold and warm paths
- **WHEN** 在相同四篇合法候选下分别执行冷缓存与热缓存提交
- **THEN** 可从不含内容的计数比较 Notes 读取次数及各阶段耗时，不能将估算当作实际测量
