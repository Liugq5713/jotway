# application-matching Specification

## Purpose

让用户通过应用名称、备用名称、短缩写或有限拼写错误找到本机应用，同时维持 Jotway 只显示一个应用候选的轻量交互，并保护普通草稿、显式选择与应用启动失败时的输入内容。

## Requirements

### Requirement: Searchable application names

系统 SHALL 使用本机应用的显示名、文件名、本地化名称和应用声明的备用名称进行匹配，保留现有中文拼音与拼音首字母能力；同一应用的多个名称 MUST 合并为同一身份。

#### Scenario: System Settings alternate names
- **WHEN** 本机 System Settings 声明 `Settings` 和 `Preferences` 备用名称，用户分别输入这些名称，且不存在同等质量的其他应用
- **THEN** 系统只推荐 System Settings，无需为它配置单独的硬编码规则

#### Scenario: Localized and phonetic names
- **WHEN** 应用目录包含微信的中英文名称，用户分别输入 `微信`、`WeChat`、`weixin`、`wx`，且该应用是唯一合格匹配
- **THEN** 系统推荐同一应用，大小写与拼音声调差异不阻止匹配

#### Scenario: Missing aliases and duplicate names
- **WHEN** 应用没有备用名称、某名称重复，或同一路径经符号链接重复出现
- **THEN** 系统仍使用可读名称匹配，同一身份不会重复参与结果排序

### Requirement: Bounded application queries

系统 SHALL 对整个应用查询进行匹配。新增的片段、缩写与误拼匹配仅用于去首尾空白后含 2 至 32 个字母或数字的单词查询，或显式打开命令中的同类目标；现有完整名称及名称前缀输入仍可包含空格。普通句子和多行正文 MUST NOT 被整体压缩成字母串参与新增模糊匹配。

#### Scenario: Later word and abbreviation
- **WHEN** 用户分别输入 `settings`、`setting`、`sett`、`ss`、`sysset`，System Settings 是唯一合格匹配
- **THEN** 系统推荐 System Settings，未按 Enter 前不打开应用

#### Scenario: Whole sentence remains ordinary input
- **WHEN** 用户在自动路由中输入 `review settings tomorrow` 或 `今天调整系统设置后写总结`，且未命中内置 action 前缀或打开命令
- **THEN** 不因其中的 `settings`、`设置` 或零散字母而新增应用推荐，继续原有 action 路由

#### Scenario: Explicit launch with adjacent content
- **WHEN** 用户输入 `打开 settting` 后换行追加正文，System Settings 是唯一合格匹配
- **THEN** 系统仅使用首行打开命令的目标进行应用匹配；追加正文不被纳入查询，也不被当作纯启动文字删除

#### Scenario: Very short and oversized input
- **WHEN** 用户输入无使用记录的一字母前缀 `s`，或超过 32 个字母且不满足现有完整名称或前缀规则的文本
- **THEN** 系统不使用新增模糊匹配强选应用；既有短前缀使用历史规则不因本次变更被扩大

### Requirement: Graded application matching

系统 SHALL 依次优先考虑完整名称或备用名称、名称前缀、后续单词前缀、连续片段、顺序缩写和拼写容错。较弱类型的应用 MUST NOT 因使用次数较高而越过较强匹配；同类型中优先考虑词首、连续性更好的匹配。

#### Scenario: Exact alternate name beats a popular weaker match
- **WHEN** 一个应用的备用名称恰好为 `Settings`，另一个经常使用的应用仅在名称中包含 `settings`
- **THEN** 输入 `settings` 时优先推荐准确匹配备用名称的应用

#### Scenario: Ordered abbreviation
- **WHEN** 用户输入 `ss` 或 `sysset`，System Settings 的匹配质量超过阈值且没有同等质量的其他应用
- **THEN** 系统允许跳过名称中间字符，推荐 System Settings

#### Scenario: Accurate spelling beats typo recovery
- **WHEN** 某应用完整名称为 `Settting`，System Settings 只能通过误拼容错匹配该输入
- **THEN** 系统推荐名为 Settting 的应用

### Requirement: Single-edit typo fallback

系统 SHALL 仅在没有合格的非误拼匹配时，对 4 至 32 个 ASCII 字母组成的单词查询尝试一次插入、删除、替换或相邻交换；匹配目标为真实名称中同首字母的单词或其前缀，且目标片段至少 4 个字母。系统 MUST NOT 对中文、拼音生成词、缩写或整句进行拼写编辑容错。

#### Scenario: Extra letter in setting
- **WHEN** 用户输入 `settting`，System Settings 是唯一符合单次编辑条件的应用
- **THEN** 系统通过与 `Settings` 的 `Setting` 前缀比较推荐 System Settings，输入框仍保留原文 `settting`

#### Scenario: Adjacent transposition
- **WHEN** 用户输入 `setitngs`，System Settings 是唯一符合单次编辑条件的应用
- **THEN** 系统允许交换一组相邻字母后匹配 Settings

#### Scenario: Typo limits do not expand indefinitely
- **WHEN** 查询为 `setttting`、`xettings` 或需要纠正中文/拼音生成词的输入，且没有合格的准确或缩写匹配
- **THEN** 系统不通过多次编辑、修改首字母或中文拼写推断强选 System Settings

### Requirement: Single application recommendation

系统 SHALL 在内部比较所有合格应用，并在自动路由的目标按钮上最多显示一个应用建议；本地应用 SHALL 不加入手动目标菜单或键盘轮换，两者只提供适用的 Notes 和 Codex 候选。存在合格匹配时系统 SHALL 推荐排序后的一个应用；排序依次为匹配类别与质量、成功打开次数、最近打开时间、规范化显示名字典序和稳定应用 id。系统 MUST NOT 因同质量与同使用记录的并列而隐藏全部应用，且结果不得受目录枚举顺序或诊断数量截断影响。

#### Scenario: Multiple internal matches produce one visible app
- **WHEN** 内部有多个匹配，但其中一个的匹配质量严格最高
- **THEN** 自动路由只在目标按钮呈现该应用，仍可经 Enter 确认启动；不创建应用结果列表，也不把任何应用加入手动菜单或键盘轮换

#### Scenario: Usage resolves an equal-quality tie
- **WHEN** 两个应用匹配质量相同，其中一个的成功打开次数更高，或次数相同但最近打开时间更晚
- **THEN** 只推荐使用记录明确胜出的应用，不记录或学习用户输入的新搜索词

#### Scenario: Unresolved tie selects one stable application
- **WHEN** 两个不同身份应用的匹配质量与使用记录都相同或没有使用记录
- **THEN** 按规范化显示名字典序升序、再按稳定应用 id 升序推荐一个，不发模型请求；交换目录枚举顺序或存在超过 32 个并列项均不改变选出的身份

#### Scenario: Voice prefix keeps an application recommendation
- **WHEN** 用户输入 `voice`，Voice Memos 与 VoiceOver Utility 是同质量前缀匹配，且均无使用记录
- **THEN** 只推荐 Voice Memos，不因并列回退到默认 action

#### Scenario: Usage precedes name ordering
- **WHEN** `voice` 同质量匹配 Voice Memos 与 VoiceOver Utility，而 VoiceOver Utility 打开次数更多，或次数相同但打开时间更新
- **THEN** 推荐 VoiceOver Utility；名称排序不得覆盖更强使用信号

### Requirement: Explicit selection precedence

系统 SHALL 保持显式选择、内置 action 前缀和应用建议之间的既有优先级；已退出的自定义 Local Rules MUST NOT 参与目标选择。手动选择 Notes 或 Codex 后，后续自动应用匹配 MUST NOT 替换该选择；选择 Let Jotway Choose 后 SHALL 按当前草稿重新匹配应用。

#### Scenario: Explicit action survives application query changes
- **WHEN** 用户显式选择 Notes 或 Codex 后把草稿改为可匹配应用的文字
- **THEN** 目标保持为该 action；选择 Let Jotway Choose 后才按当前草稿重新决定应用建议，应用不加入手动菜单或键盘轮换

#### Scenario: Explicit action and local rules still win
- **WHEN** 草稿能匹配应用，但用户已显式选择 Apple Notes，或存在命中的内置 action 前缀
- **THEN** 新匹配能力不改变该既有路由优先级；保留原有 action 选择操作与提交方式

#### Scenario: Manual selection does not list the automatic application
- **WHEN** 自动路由已在目标按钮显示匹配的应用，用户打开目标菜单或轮换目标
- **THEN** 手动候选仍仅包含适用的 Notes 和 Codex；菜单保留 Let Jotway Choose，确认应用启动的既有路径不受影响

### Requirement: Snapshot-safe execution

系统 SHALL 仅在用户确认时启动当前显示且通过复核的应用。执行与清理草稿 MUST 使用同一次匹配的快照边界；应用变化、失败、输入组合或迟到结果不得执行旧目标、覆盖新输入或删除附带正文。

#### Scenario: Pure fuzzy launch clears its own draft
- **WHEN** 用户确认由 `settings`、`ss`、`voice` 或 `settting` 排序选出的应用，启动成功且草稿与路由快照仍相同
- **THEN** 按既有成功流程清除这次纯启动草稿，并只记一次成功打开

#### Scenario: Failed or stale launch preserves input
- **WHEN** 应用启动失败，或启动回调前用户已编辑、清空或开启另一份草稿
- **THEN** 失败保留可恢复的原草稿；旧结果不覆盖或清空更新后的文字，不把失败计为成功使用

#### Scenario: Catalog changes before confirmation
- **WHEN** 确认复核期间目录刷新使排序选出的身份改变、目标消失或身份变化
- **THEN** 旧建议失效；本次确认不悄悄执行另一个应用或默认 action，原草稿保留

#### Scenario: Composition and menu confirmation stay unchanged
- **WHEN** 中文输入尚在组合中，或用户在目标菜单按 Enter 选择目标
- **THEN** 组合中的按键优先交给输入法；菜单 Enter 只确认选择并回到编辑区，不直接提交

### Requirement: Local responsive matching

系统 SHALL 使用本机已准备的应用目录完成匹配；合格的本地匹配与并列排序不依赖 AI 或网络。按键期间 MUST NOT 重新扫描磁盘、读取应用包或重新生成全部拼音；后台刷新继续保持旧快照可用，并拒绝过期结果。

#### Scenario: Matching without a model or network
- **WHEN** 模型未配置或网络离线，用户输入有唯一合格结果的 `settting`
- **THEN** 系统仍能即时给出唯一应用建议，不等待模型防抖或网络返回

#### Scenario: Refresh does not rewrite the draft
- **WHEN** 应用目录在输入期间后台刷新或发布新快照
- **THEN** 编辑区原文与输入组合不被改写；下一次有效识别消费完整的新快照，不混用两个目录版本

### Requirement: Compatible matching diagnostics

系统 SHALL 在既有本地诊断中区分准确、前缀与新增匹配类型，并继续读取旧的匹配记录。系统 MUST NOT 因本次匹配改动新增搜索词上传或持久化的搜索词学习历史。

#### Scenario: Existing records remain readable
- **WHEN** 新版本读取包含原有准确或前缀类型的操作记录并导出复盘数据
- **THEN** 原记录正常读取，新增匹配类型可识别；未知类型不会使整条记录解码失败
