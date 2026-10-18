# notes-ai-presentation Specification

## Purpose

定义 Jotway 存入 Apple Notes 时生成内容的稳定阅读结构，让用户清楚区分原文、AI 洞察和相关来源，并使视觉排版变化不会破坏原文保存、来源跳转或历史索引边界。

新生成内容仅包含 AI 洞察，不再生成相关内容或来源链接。下文涉及相关内容的格式与链接规则仅约束已有笔记的兼容读取和打开；不授权新历史检索或生成。

## Requirements

### Requirement: Ordered optional generated sections

系统 SHALL 完整保留原文；普通新建 SHALL 先显示独立的首次标题、一个空行，再显示完整原文，不增加归集时间标记；归集笔记先显示主题，不再显示主题下单独的日期行，再按提交顺序呈现简短时间标记和原始条目，具体格式遵循 Compact grouped timeline。仅在最终采用至少一条生成内容时，在原文之后显示一条可见分隔线，再依次呈现非空的洞察区与相关内容区。空区块 SHALL 整体省略；本展示能力 SHALL 沿用生成模块的有效条目、顺序和数量约束，不自行缩减为一条或扩展上限。

#### Scenario: Both sections are present
- **WHEN** 最终采用的结果同时包含洞察和两条相关内容
- **THEN** 独立标题及适用的时间标记之后，顺序为完整原文、一个分隔线、洞察区、相关内容区，分隔线不在两个生成区之间重复出现
- **AND** 各条目保持生成模块确定的顺序

#### Scenario: Only one section is present
- **WHEN** 仅有洞察，或仅有相关内容
- **THEN** 原文之后仅显示一个分隔线和对应的非空区块，不显示另一区块标题或占位内容

#### Scenario: No accepted generated content
- **WHEN** AI 关闭、无增量结果、超时、服务失败、校验过滤或来源边界记录失败导致最终采用结果为空
- **THEN** 普通新建仍显示首次标题或临时标题及完整原文；归集笔记仅保留主题与简短时间标记的原文时间线，不显示单独日期行、分隔线、空生成标题或失败占位

#### Scenario: Multiple insights remain visible
- **WHEN** 生成模块在其有效数量约束内提供多条合格洞察
- **THEN** 所有合格洞察在同一个洞察标题下呈现，各条之间空一行，排版不改变实际采用计数

#### Scenario: Previous additions are stale
- **WHEN** 归集笔记已追加新原文，但最新生成内容尚未成功写回，且旧生成区仍存在
- **THEN** 旧生成区显示其覆盖到的原始条目时间及“尚未包含最新想法”的简短说明；不展示内部版本号或把旧分析当作最新分析
- **AND** 新结果写回后删除过期说明；合法空结果删除旧生成区及说明

### Requirement: Localized plain section headings

系统 SHALL 延续按草稿语言选择生成区标签的规则。中文标题 SHALL 为「AI 洞察」「相关内容」，其他语言沿用英文回退「AI Insights」「Related Content」。生成区 SHALL 使用系统正文样式左对齐，标题加粗，无引用块缩进、首行缩进或额外的「AI 整理」副标题。

#### Scenario: Chinese draft in English app interface
- **WHEN** 应用界面为英文且草稿被识别为中文
- **THEN** 笔记中使用「AI 洞察」「相关内容」，两个标题均加粗且与正文左边缘对齐

#### Scenario: English draft
- **WHEN** 草稿被识别为英文
- **THEN** 标题使用「AI Insights」「Related Content」，来源前缀使用「Source:」

### Requirement: Single blank line rhythm

系统 SHALL 在每个生成区标题与首条正文之间保留恰好一个空行；相邻相关条目之间 SHALL 恰好空一行。每条关联说明与自身来源之间 SHALL 只换行、不插入空行。生成区之间 SHALL 空一行。规则只约束应用生成的留白，不得删减原文自带的空行。

#### Scenario: Heading spacing
- **WHEN** 一篇笔记同时显示两个生成区
- **THEN** 「AI 洞察」与其正文之间、「相关内容」与其第一条正文之间，分别可见一个空行

#### Scenario: Adjacent related entries
- **WHEN** 相关内容包含两条记录
- **THEN** 第一条来源行与第二条说明之间只有一个空行，不出现两个叠加空行
- **AND** 每条来源行紧接对应说明的下一行

#### Scenario: Naturally wrapped content
- **WHEN** 关联说明或来源标题因窗口宽度自动折行
- **THEN** 自动折行不被当成额外段落，条目间仍只插入一个空行

### Requirement: Inline source attribution

中文来源行 SHALL 显示为「来源：《短标题》↗」，英文为「Source: 短标题 ↗」；标题装饰和箭头 SHALL 属于同一个可点击链接。标题与链接 SHALL 来自已验证的真实来源，沿用现有标题清理、48 字符上限、空标题回退和本机打开行为；不得使用模型生成的标题、示例 URL、日期或额外来源清单。

#### Scenario: Open a related note
- **WHEN** 用户点击一条相关内容的来源标题或箭头
- **THEN** 通过既有本机来源跳转打开同一条原备忘录；名称相同的不同笔记仍按真实来源标识区分

#### Scenario: Long empty or special source title
- **WHEN** 真实来源标题为空、超过现有上限或包含 HTML 特殊字符
- **THEN** 使用既有空标题回退或截短规则，并将标题作为文字安全显示，来源行不产生额外标签或链接

#### Scenario: Source cannot be opened
- **WHEN** 来源后来被删除、权限不足或本机缺少链接处理程序
- **THEN** 不伪造另一条来源，不创建共享链接；维持现有跳转失败提示或系统处理行为

### Requirement: Original text and generated boundary

系统 SHALL 在显示及纯文字表示中仅完整保留原文一次，延续空白与特殊字符保护。分隔线、生成标题、正文、来源前缀、标题装饰和箭头 SHALL 全部归入生成尾部，并从后续历史索引排除。普通新建的独立标题以及归集笔记的主题标题、时间标记与刷新状态 SHALL 作为展示元数据排除，所有原始条目 SHALL 保留可验证的顺序边界；每次更新后只索引当前完整版本。仅出现「AI 洞察」或「相关内容」等普通文字 SHALL 不构成删除或截断原文的依据。

#### Scenario: Whitespace and heading-like original
- **WHEN** 原文包含缩进、重复空行、Markdown、特殊字符或单独一行「相关内容」
- **THEN** 原文文字与顺序保持不变，标题样文字不会被当作本次生成区截断

#### Scenario: New formatted note read back
- **WHEN** 新格式笔记写入后 HTML 属性被 Notes 简化，但本地原文与生成尾部记录仍与完整正文匹配
- **THEN** 后续索引只提取原文，分隔线及来源装饰不会造成错误匹配或进入索引

#### Scenario: Unproven new-format boundary
- **WHEN** 只能识别新格式的分隔线与标题组合或残留生成标识，且没有完整可验证的原文边界
- **THEN** 将该笔记标记为边界不明并跳过，不仅凭短标题或共享前缀推断原文

#### Scenario: Existing saved notes
- **WHEN** 读取旧标题和旧引用块格式的笔记
- **THEN** 保留现有旧格式识别及边界记录能力，不重写旧笔记，不删除已有边界记录

#### Scenario: Grouped original entries survive refresh
- **WHEN** 一篇主题笔记追加原始条目并替换生成区，Notes 在回读时简化 HTML 属性
- **THEN** 经完整版本与边界验证后，归类、生成和历史索引读取每条原文各一次，不读取模型标题、时间标记、状态或生成内容作为原文
- **AND** 无法证明完整边界时跳过自动更新与索引，不根据可见标题猜测并覆盖

#### Scenario: Title replacement preserves original extraction
- **WHEN** 普通笔记由临时标题改为 AI 标题且 Notes 简化了 HTML 属性
- **THEN** 完整版本及标题、原文、生成尾部边界仍可核实；仅提取完整原文，标题不作为原文或洞察进入索引
- **AND** 边界不明时停止自动更新与索引，不通过删除可见首行猜测原文

### Requirement: Saved rendering acceptance

系统 SHALL 通过正式存入使用的 HTML 表示生成可读版式，分隔线与留白不得依赖保存后的手工编辑。验收 SHALL 区分文本组装检查与 Notes 实际显示；浅色和深色模式中的标题、正文、分隔线及来源均须可读，不要求跨版本保留相同像素尺寸或原生折叠能力。

#### Scenario: One-write visual result
- **WHEN** 使用最终渲染器输出一次性写入包含两个生成区的测试笔记
- **THEN** 无需再次粘贴、删除空行或调整格式，就显示约定的分隔线、标题间距、条目间距和来源链接

#### Scenario: Native display verification remains pending
- **WHEN** 仅完成编译、纯文字或 AppKit 转换检查，尚未检查 Notes 实际写入结果
- **THEN** 交付记录明确将真实显示验收列为待完成，不宣称已复现用户确认的版式

### Requirement: Compact grouped timeline

归集笔记 SHALL 在每条原文前显示独立的 `- HH:mm` 时间行，使用提交时区的 24 小时制，不显示秒或时区后缀。标题到首条时间、时间到正文、正文到下一条时间 SHALL 分别插入一个空行；该留白不包含原文自带的首尾空行，原文 SHALL 不被裁剪或缩进。完整提交时间、时区、身份及顺序 SHALL 保留，继续用于既有归集和恢复规则。时间标记与留白 SHALL 属于展示元数据，不作为用户原文进入历史索引。

#### Scenario: New grouped note
- **WHEN** 用户在提交时区的 10:30:45 提交一条不带首尾空行的原文，系统创建归集笔记
- **THEN** 正文依次显示主题、一个空行、`- 10:30`、一个空行和完整原文；主题下没有额外日期行
- **AND** HTML 与纯文字表示的可见文字和顺序一致，用户正文不进入缩进列表

#### Scenario: Multiple entries within one minute
- **WHEN** 同一分钟内两次提交被归入同一篇笔记
- **THEN** 两条原文各自保留相同的分钟时间标记，按原有提交顺序出现，不去重、不合并，也不以展示时间代替提交身份

#### Scenario: Original whitespace and time-like text
- **WHEN** 原文包含首尾空行、缩进、代码、日期或 `- 10:30` 等时间样文字
- **THEN** 保留原文全部内容和空白，只额外插入约定的展示留白；完整边界回读后仅提取真实原文，不把原文中的时间样文字作为元数据删除

#### Scenario: Refresh keeps the compact timeline
- **WHEN** 同一篇归集笔记追加原文、保留旧生成区或成功替换 AI 结果
- **THEN** 每次写入都使用相同的简短时间线；AI 洞察、相关内容、来源链接、分隔线与旧结果覆盖提示沿用既有内容和展示规则

#### Scenario: Ordinary save remains unchanged
- **WHEN** 用户关闭归集并通过普通存入保存草稿
- **THEN** 保留完整原文，按首次标题规则添加独立标题或临时标题，不添加归集时间标记

### Requirement: Compatible timeline updates

系统 SHALL 继续通过原有完整版本和原文边界读取旧格式笔记；仅在既有规则允许的当天追加或刷新实际发生时使用新格式重绘。单纯读取、升级或格式变化 SHALL 不触发批量改写，不扩大当天可写范围。边界无法验证或检测到手动修改时 SHALL 沿用既有保护与降级行为，不凭可见时间或标题推断原文。

#### Scenario: Valid current-day old-format note
- **WHEN** 当天旧格式受管理笔记的完整版本及边界仍合法，且发生合法追加或 AI 刷新
- **THEN** 保留全部原文及其身份、顺序和完整时间，写入新展示格式，并使后续回读和索引继续正确区分原文与元数据

#### Scenario: Historical or edited note
- **WHEN** 笔记属于往日，或旧格式笔记的完整边界因手动编辑而不再匹配
- **THEN** 不因本次格式调整而重排该笔记；新提交与刷新继续遵守既有日期范围、冲突保护及失败恢复规则
