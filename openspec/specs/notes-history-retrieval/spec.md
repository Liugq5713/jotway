# notes-history-retrieval Specification

## Purpose

为 Notes 的 AI 补充提供范围正确、有界且内容有效的历史候选，并让用户通过 Search History 核对候选数量和索引覆盖限制，避免将单篇展示、部分索引或空结果误解为已完整搜索全部历史。

## Requirements

### Requirement: Bounded distinct-source candidates

系统 SHALL 在当前允许的文件夹范围内筛选历史候选，最多提供十篇不同来源，每篇片段最多 400 字符，片段合计最多 8000 UTF-8 字节；最终历史展示上限独立保持五篇。系统 SHALL 保留余弦距离不大于 0.35 的门槛及文本/来源去重，不通过降低相关性要求填满数量。

#### Scenario: More than five eligible sources
- **WHEN** 检索窗口中有八篇通过质量和距离筛选的不同来源，片段总字节数低于预算
- **THEN** 八篇均可进入模型候选，而非在第五篇截断；最终展示仍不超过五篇

#### Scenario: Duplicate note and byte budget
- **WHEN** 同一篇笔记有多个命中片段，其他候选存在重复文本，且全部有效片段超过总字节预算
- **THEN** 每篇只保留一个有效片段，重复文本不重复占位，按相关性在预算内选取来源
- **AND** 不能将十篇上限解释成保证提供十篇

#### Scenario: Scope and distance remain enforced
- **WHEN** 范围外来源最相似，范围内来源超过距离门槛
- **THEN** 二者均不进入本次候选，不能因为候选不足放宽文件夹范围或门槛

### Requirement: Quality filtering before candidate limits

系统 SHALL 在应用十篇候选上限前排除标签、缺少有效上下文的笼统片段，以及与当前草稿完全重复或包含当前草稿全文的片段。较前候选被排除时 SHALL 继续考察同一有界检索窗口中的后续候选，不额外调用模型扩写查询或扩大授权范围。

#### Scenario: Invalid early results do not consume slots
- **WHEN** 检索窗口前五个命中是标签、笼统提议或当前草稿重复内容，后面有三篇有效相关来源
- **THEN** 三篇有效来源均可进入候选，不能因先截取前五篇而得到空列表

#### Scenario: Later valid chunk from the same source
- **WHEN** 同一来源最靠前的片段无效，但稍后的命中片段有效且未超预算
- **THEN** 无效片段不提前占用该来源的去重名额，有效片段仍可成为该来源的候选

### Requirement: Explainable retrieval results

每次检索 SHALL 提供不含内容的数量摘要，区分原始命中片段、距离筛选后片段、内容筛选和去重后来源、实际送入候选的来源及字节数。摘要 SHALL 属于本次检索版本和范围，错误状态不得冒充成功的零命中；计数缺失不得默认为零。

#### Scenario: Filtered versus selected sources
- **WHEN** 原始命中有十二个片段，八个通过距离筛选，内容筛选和去重后有六篇，预算允许五篇
- **THEN** 摘要分别提供 12、8、6、5 及实际片段字节数，后续生成诊断使用本次五篇候选数

#### Scenario: Retrieval error is not no hits
- **WHEN** 查询向量生成失败或索引读取失败
- **THEN** 返回可区分的失败状态；用户和日志不会看到代表成功检索的“零候选”结论

### Requirement: Inspect candidates and coverage

Search History SHALL 使用与存入前检索相同的候选筛选与预算，显示本次候选来源数、来源标题/片段/打开入口，以及同一范围内可搜索、待处理和失败数量。存在待处理、失败或尚无完整同步记录时 SHALL 提示结果可能不完整；SHALL NOT 以已知源数计算未知全部 Notes 的完成率或声称完整覆盖。

#### Scenario: Inspect a partially indexed library
- **WHEN** 本次检索快照中有 153 篇可搜索、260 篇待处理、3 篇失败，并返回两篇候选
- **THEN** 页面区分显示两篇候选与这些覆盖数量，提示部分笔记尚不可搜索，不将两篇称为全部相关历史
- **AND** 提示中允许用户使用现有 Refresh 入口继续索引，不自动重建或清空索引

#### Scenario: Inspection and save use the same policy
- **WHEN** Search History 与确认存入使用相同草稿、索引版本、范围及等价查询向量
- **THEN** 二者产生相同候选来源及顺序；页面说明候选供 AI 筛选，最终历史条数可能更少

#### Scenario: Search becomes stale
- **WHEN** 用户编辑查询、切换范围或本次索引版本失效
- **THEN** 旧候选及其数量/覆盖摘要一同失效，不与新查询或新范围的状态混合显示

### Requirement: Retrieval lifecycle compatibility

系统 SHALL 保留首次 Index Notes 的显式启动、既有自动刷新和 Clear Index 暂停约定；检索不触发全量同步、权限申请或索引重建。没有可用索引时 SHALL 允许原文存入与仅基于草稿的 AI 补充，且不得声称已检索个人历史。

#### Scenario: History disabled or cleared
- **WHEN** Related History 关闭、缺少 embedding key 或索引被清空后尚未再次启动
- **THEN** 本次存入不查询历史，不为了凑候选启动索引，其他已启用的文字补充仍可运行

#### Scenario: Empty successful retrieval
- **WHEN** 有效检索没有任何合格来源
- **THEN** 历史区省略，生成可以仅基于草稿；诊断记录成功零命中，不能添加伪造来源
