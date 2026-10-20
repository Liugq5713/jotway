# Spec Delta

## MODIFIED Requirements

### Requirement: Ordered optional generated sections

新的 Notes 内容 SHALL 包含独立标题、一个空行和完整原文，或按 Compact grouped timeline 显示主题标题和按时序排列的完整原文。系统 SHALL NOT 新增洞察、相关内容、分隔线、生成标题、空占位或分析覆盖提示。已存生成内容 SHALL 仅按 Legacy generated content preservation 保留。

#### Scenario: New ordinary note
- **WHEN** 关闭归集后保存草稿
- **THEN** 笔记包含语义标题或待生成标题以及完整原文一次，不添加归集时间或生成区

#### Scenario: New grouped note or append
- **WHEN** 草稿新建或加入受管理的当天主题
- **THEN** 完整原文按提交顺序与简短时间标记显示，不添加 AI 分析

#### Scenario: Original contains insight headings
- **WHEN** 草稿自身包含“AI Insights”、“AI 洞察”、分隔线或来源样文字
- **THEN** 这些字符仍是原文，不删除或当作生成区


#### Scenario: Both sections are present
- **WHEN** 合法旧笔记包含已验证的洞察与相关内容两个区域
- **THEN** 允许的追加保留既有顺序和来源链接，不重新生成任一区域

#### Scenario: Only one section is present
- **WHEN** 合法追加的旧笔记只有一个已验证生成区
- **THEN** 保留该区域，不添加另一个区域、标题或占位

#### Scenario: No accepted generated content
- **WHEN** 保存新的普通或归集笔记
- **THEN** 仅输出标题、完整原文及适用的时间线元数据，不添加生成分隔线、标题或失败占位

#### Scenario: Multiple insights remain visible
- **WHEN** 已验证旧尾部含多条洞察且笔记发生合法追加
- **THEN** 保留全部旧洞察，不筛选、扩展或刷新

#### Scenario: Previous additions are stale
- **WHEN** 新原文加入带旧生成尾部的笔记
- **THEN** 尾部及已有覆盖提示保持不变，不新建覆盖提示或刷新任务

### Requirement: Inline source attribution

已存来源链接 SHALL 继续通过既有本地处理器打开原来存储的 Notes 来源标识。移除补充 SHALL NOT 创建替代链接、按标题重定向或生成新来源。可验证的旧 HTML SHALL 保留既有链接；仅能验证纯文字时无需重建丢失的链接标记。

#### Scenario: Open a related note
- **WHEN** 用户点击已存的来源标题或箭头
- **THEN** 处理器使用原来源 ID，即使其他笔记同名

#### Scenario: Source cannot be opened
- **WHEN** 旧来源已删除或不可用
- **THEN** 沿用现有失败行为，不替换来源或创建共享链接


#### Scenario: Long empty or special source title
- **WHEN** 保留的旧来源标题很长、为空或含特殊字符
- **THEN** 保留已验证文字；纯文本降级安全转义，不生成新来源标题或链接

### Requirement: Original text and generated boundary

系统 SHALL 在显示及纯文字表示中仅完整保留原文一次，延续空白与特殊字符保护。分隔线、生成标题、正文、来源前缀、标题装饰和箭头 SHALL 全部归入生成尾部，并从后续回顾排除。普通新建的独立标题以及归集笔记的主题标题、时间标记与刷新状态 SHALL 作为展示元数据排除，所有原始条目 SHALL 保留可验证的顺序边界；每次更新后仅从当前完整版本提取原文。仅出现「AI 洞察」或「相关内容」等普通文字 SHALL 不构成删除或截断原文的依据。

#### Scenario: Whitespace and heading-like original
- **WHEN** 原文包含缩进、重复空行、Markdown、特殊字符或单独一行「相关内容」
- **THEN** 原文文字与顺序保持不变，标题样文字不会被当作本次生成区截断

#### Scenario: New formatted note read back
- **WHEN** 新格式笔记写入后 HTML 属性被 Notes 简化，但本地原文与生成尾部记录仍与完整正文匹配
- **THEN** 后续回顾只提取原文，分隔线及来源装饰不会造成错误匹配或成为用户证据

#### Scenario: Unproven new-format boundary
- **WHEN** 只能识别新格式的分隔线与标题组合或残留生成标识，且没有完整可验证的原文边界
- **THEN** 将该笔记标记为边界不明并跳过，不仅凭短标题或共享前缀推断原文

#### Scenario: Existing saved notes
- **WHEN** 读取旧标题和旧引用块格式的笔记
- **THEN** 保留现有旧格式识别及边界记录能力，不重写旧笔记，不删除已有边界记录

#### Scenario: Grouped original entries survive refresh
- **WHEN** 一篇主题笔记追加原始条目并保留既有生成尾部，Notes 在回读时简化 HTML 属性
- **THEN** 经完整版本与边界验证后，归类和回顾读取每条原文各一次，不读取模型标题、时间标记、状态或生成内容作为原文
- **AND** 无法证明完整边界时跳过自动更新与回顾原文提取，不根据可见标题猜测并覆盖

#### Scenario: Title replacement preserves original extraction
- **WHEN** 普通笔记由临时标题改为 AI 标题且 Notes 简化了 HTML 属性
- **THEN** 完整版本及标题、原文、生成尾部边界仍可核实；仅提取完整原文，标题不作为原文或洞察成为回顾依据
- **AND** 边界不明时停止自动更新与回顾原文提取，不通过删除可见首行猜测原文

### Requirement: Saved rendering acceptance

系统 SHALL 使用正式 Notes HTML 写入器产生可读的标题与原文版式。验证 SHALL 区分文字组装和真实 Notes 显示。原文、标题、简短时间标记及旧内容 SHALL 在浅色和深色模式可读，不要求不同 Notes 版本的像素一致。

#### Scenario: One-write visual result
- **WHEN** 最终渲染器创建新的普通或归集笔记
- **THEN** 标题、原文空白和时间线无需人工修复格式，不包含生成区

#### Scenario: Native display verification remains pending
- **WHEN** 只运行了构建、纯文本或 AppKit 转换检查
- **THEN** 交付记录明确真实 Notes 显示仍待人工验收


### Requirement: Compact grouped timeline

归集笔记 SHALL 在每条原文前显示独立的 `- HH:mm` 时间行，使用提交时区的 24 小时制，不显示秒或时区后缀。标题到首条时间、时间到正文、正文到下一条时间 SHALL 分别插入一个空行；该留白不包含原文自带的首尾空行，原文 SHALL 不被裁剪或缩进。完整提交时间、时区、身份及顺序 SHALL 保留，继续用于既有归集和恢复规则。时间标记与留白 SHALL 属于展示元数据，不作为用户原文进入回顾。

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
- **WHEN** 同一篇归集笔记追加原文并保留既有生成尾部
- **THEN** 每次写入都使用相同的简短时间线；既有生成尾部及其已有覆盖提示按 Legacy generated content preservation 保留，不新增或刷新分析及覆盖提示

#### Scenario: Ordinary save remains unchanged
- **WHEN** 用户关闭归集并通过普通存入保存草稿
- **THEN** 保留完整原文，按首次标题规则添加独立标题或临时标题，不添加归集时间标记

### Requirement: Compatible timeline updates

系统 SHALL 继续通过原有完整版本和原文边界读取旧格式笔记；仅在既有规则允许的当天追加实际发生时使用新格式重绘。单纯读取、升级或格式变化 SHALL 不触发批量改写，不扩大当天可写范围。边界无法验证或检测到手动修改时 SHALL 沿用既有保护与降级行为，不凭可见时间或标题推断原文。

#### Scenario: Valid current-day old-format note
- **WHEN** 当天旧格式受管理笔记的完整版本及边界仍合法，且发生合法追加
- **THEN** 保留全部原文及其身份、顺序和完整时间，写入新展示格式，并使后续回读和回顾原文提取继续正确区分原文与元数据

#### Scenario: Historical or edited note
- **WHEN** 笔记属于往日，或旧格式笔记的完整边界因手动编辑而不再匹配
- **THEN** 不因本次格式调整而重排该笔记；新提交与标题恢复继续遵守既有日期范围、冲突保护及失败恢复规则

## ADDED Requirements

### Requirement: Legacy generated content preservation

升级、启动和读取 SHALL NOT 改写旧 Notes 内容。合法的当天追加 SHALL 保留已验证旧生成文字及已有覆盖元数据，将其放在原文区域之外；SHALL NOT 刷新或新增覆盖提示。标题恢复 SHALL 保留所有非标题区域。无法验证边界时 SHALL 阻止更新旧笔记并沿用独立保存降级。

#### Scenario: Append to a note with old insights
- **WHEN** 合法受管理笔记包含已验证旧生成尾部且收到相关草稿
- **THEN** 新原文加入尾部之前的时间线，旧洞察和已有覆盖文字完整保留而不重新生成
- **AND** 归类与回顾不将尾部作为用户证据

#### Scenario: Legacy markup is lost
- **WHEN** Notes 已移除 HTML 标记但完整纯文字边界仍可验证
- **THEN** 保留经验证的生成文字及已有覆盖文字，无需重建丢失的来源链接展示

#### Scenario: Legacy boundary is uncertain
- **WHEN** 手动编辑或不完整边界使区域无法可靠恢复
- **THEN** 旧笔记保持原样，新提交沿用独立保存降级，不猜测需要删除哪些文字

## REMOVED Requirements

### Requirement: Localized plain section headings

**Reason**: 移除新生成区域。
**Migration**: 按 Legacy generated content preservation 保留旧内容，不重新生成版式或文字。

### Requirement: Single blank line rhythm

**Reason**: 移除新生成区域。
**Migration**: 按 Legacy generated content preservation 保留旧内容，不重新生成版式或文字。
