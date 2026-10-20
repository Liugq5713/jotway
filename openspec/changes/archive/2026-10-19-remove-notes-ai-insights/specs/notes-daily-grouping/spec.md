# Spec Delta

## MODIFIED Requirements

### Requirement: Daily writable scope

系统 SHALL 仅将当前 Notes 存入文件夹内、当前本地自然日创建且由归集功能管理的笔记作为追加目标。只读回顾 SHALL 沿用自己的授权范围，与写入范围独立；昨天及更早笔记仅可读取，不发起关联检索。系统 SHALL 不批量合并、搬迁或删除旧笔记，不因旧笔记今天被修改而使其可写。

#### Scenario: Same project on different days
- **WHEN** 昨天已有 Jotway 项目笔记，今天首次提交该项目想法
- **THEN** 在当前存入文件夹创建今天的项目笔记，昨天的笔记保持原样，并仅可在用户请求的回顾范围内读取

#### Scenario: Matching note outside writable scope
- **WHEN** 相关笔记位于其他文件夹、早于今天创建或尚未由归集功能管理
- **THEN** 不向它追加，不重命名或接管它；仅可按独立回顾范围读取，不为本次归集检索它

#### Scenario: Midnight or time zone changes
- **WHEN** 提交排队期间进入下一本地自然日，或时区变化使原候选不再属于当天
- **THEN** 写入前重新判断当日范围，在当前日重新选择目标；保留原始提交时间，不写入已成为往日的笔记
- **AND** 已保存笔记的迟到分类或标题结果跨日后不得再写回

### Requirement: Protected note updates

系统 SHALL 在修改前核实笔记身份、文件夹、日期、可读写状态和完整内容版本。已检测到的手动编辑、移动、删除、附件、共享或锁定状态 SHALL 阻止自动覆盖。原文写入与标题补全 SHALL 分开确认，SHALL NOT 发出 AI 洞察刷新写入；更新结果不明时不得当作明确失败自动重写或新建副本。缓存及修改时间 SHALL 仅辅助候选准备，不替代实际更新前的完整正文校验；减少重复读取 SHALL 保留最后一次完整写前校验及必要写后回读。

#### Scenario: User edits a managed note
- **WHEN** 写入前发现用户已修改候选笔记，完整内容与受管理版本不符
- **THEN** 保留用户修改；新想法独立保存，不更新该冲突笔记，不尝试根据标题重建并覆盖它

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

Notes 设置 SHALL 保留默认开启且尊重已存关闭值的按天归集开关。归集 SHALL 使用共享文本配置，不依赖补充、历史索引或 Personal Agent。关闭归集 SHALL 保留普通保存和独立标题生成／恢复。设置 SHALL 保留回顾控制，SHALL NOT 提供补充开关。

#### Scenario: Group with assistance disabled
- **WHEN** 归集与共享文本模型可用
- **THEN** 相关原文可加入当天主题，不请求洞察或相关历史

#### Scenario: Grouping disabled or key missing
- **WHEN** 归集关闭或模型配置不可用
- **THEN** 原文按既有标题或待生成标题规则独立保存；归集关闭时跳过分类

#### Scenario: One model serves grouping
- **WHEN** 文本模型已就绪
- **THEN** 归集使用既有活动模型和共享 AI Services 设置，不提供备用配置


### Requirement: Restart and completion semantics

重启 SHALL 恢复当天已确认笔记与提交身份，不重复追加。原文保存确认后 SHALL 仅发出一次完成提示。启动 SHALL NOT 恢复补充生成或刷新写入。旧结果不明的刷新 SHALL 保持可读并仅通过读取对账；未解决状态 SHALL 保留写入保护。既有当天标题恢复 SHALL 独立继续。

#### Scenario: Restart after original save
- **WHEN** 原文在退出前已保存而旧补充刷新未完成
- **THEN** 不重复原文，不恢复补充生成或刷新写入

#### Scenario: Restart on a later day
- **WHEN** 昨天的补充未完成
- **THEN** 不更新昨天笔记，也不为该工作创建替代笔记

#### Scenario: Upgrade with an uncertain refresh write
- **WHEN** 旧版本曾发出刷新但未确认结果
- **THEN** 保留已存身份和预期指纹，通过读取核对，绝不重复刷新写入
- **AND** 未解决的不匹配继续保护笔记，禁止盲目追加；新提交沿用既有安全降级

#### Scenario: Pending title remains valid
- **WHEN** 重启后仍满足当天标题恢复条件
- **THEN** 可仅恢复标题，不再次提示原文保存完成


### Requirement: Natural-day candidate cache

系统 SHALL 在内存中按存入文件夹、本地自然日及时区隔离当天受管理笔记的已确认完整原文与版本，仅在读取验证或写入确认后更新。缓存 SHALL 有容量上限，不新增正文落盘，不依赖已移除的历史索引或 AI 补充偏好。跨日、范围改变或归集关闭 SHALL 清理不再适用的缓存；退出后清空，重启按需恢复。缓存淘汰 SHALL 不等于排除合法候选，不得截断原文或只按标题分类。

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
- **WHEN** 原文追加、标题更新或旧不确定写入的回读核对已确认成功，或旧版本的异步结果迟到
- **THEN** 前者更新同篇缓存的完整已确认版本；后者不能覆盖新版本，失败或结果不明的写入不进入已确认缓存

### Requirement: Independent grouping deadlines

系统 SHALL 为每次提交设置包含归集排队、候选准备和分类的 300 秒决策预算，为分类保留 120 秒；候选准备及此前排队最多使用 180 秒。分类 SHALL 在候选准备完成后开始独立的 120 秒期限，包含模型排队，不再因前置十余秒耗时提前放弃。跨日重选 SHALL 共用本次总预算。预算不包含后续原文写入确认；保存后 SHALL NOT 调度 AI 补充或刷新期限。到期 SHALL 丢弃迟到结果，保持写入顺序与一次提交最多一次原文保存。无可用标题的新建 SHALL 使用首次标题规格定义的独立有限预算，不重新启动分类或延长已结束的归类决策。

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
