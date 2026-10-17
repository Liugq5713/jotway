# browser-source-capture Specification

## Purpose

让用户在 Chrome 复制片段后快速记录自己的想法，并把可检查、可编辑的网页标题和链接随原文存入 Notes，以便后续返回出处继续研究。来源获取遵循尽力关联、显式授权和失败不阻塞记录的边界。

## Requirements

### Requirement: Explicit browser source enablement

系统 SHALL 在快速记录设置提供默认关闭的 Chrome 来源开关，与剪贴板历史独立；Chrome 搜索 action 移除不改变该功能、已保存开关或自动化权限。仅用户明确启用或重试授权时 SHALL 请求 Chrome 自动化权限；说明读取复制时附近的当前页标题和链接、不能保证复制事件归属，并且来源进入草稿后沿用现有 AI、索引与本地操作记录设置。

#### Scenario: First explicit enablement
- **WHEN** 用户主动开启 Chrome 来源且尚无权限
- **THEN** 请求 Chrome 自动化授权，不创建笔记或提交草稿；授权成功后支持后续复制，不为旧剪贴板补猜来源

#### Scenario: Denied revoked or disabled
- **WHEN** 用户拒绝权限、权限被撤销或来源开关关闭
- **THEN** 保留原有文字引用与 Notes 保存；后台不反复弹授权，设置中显示可用状态及授权重试入口
- **AND** 关闭后丢弃尚未采用的来源，已经进入草稿的文字由用户编辑保留或删除

#### Scenario: Source remains available without the search action
- **WHEN** 用户升级到不再提供 Chrome 搜索 action 的版本，原来已启用来源且授权有效
- **THEN** 设置仍可管理来源，新复制仍按既有新鲜度、等待上限和失效检查附加标题与 URL；不需要恢复搜索 action 或再次启用来源

### Requirement: Best effort Chrome source association

系统 SHALL 仅在观察到新复制、当时前台应用为 Chrome 且来源功能已授权时尝试获取当前活动页标题与 URL，并与该次观察绑定。仅采用完整合法的 HTTP/HTTPS URL，保留查询参数和片段；标题缺失时以主机名回退。系统 SHALL 不将观察时的前台页声称为已证明的复制来源，不扫描其他标签或使用模型推断来源。

#### Scenario: Eligible browser copy
- **WHEN** 用户在 Chrome 复制文字，来源读取期间页面及复制版本稳定，并在既有近期引用窗口内唤起面板
- **THEN** 在引用文字后插入网页标题与完整 URL，供提交前检查；不改变复制文字的既有引用格式

#### Scenario: Detected page or clipboard change
- **WHEN** 来源读取期间检测到切换标签、页面导航、前台转向其他外部应用，或另一次复制覆盖本次内容
- **THEN** 丢弃不一致来源，不能将 A 片段配上 B 页链接；新复制只使用自身有效来源或纯文字降级

#### Scenario: Unsupported or missing source
- **WHEN** 来自非 Chrome 应用、Chrome 无可读标签、URL 非 HTTP/HTTPS 或读取错误
- **THEN** 沿用文字引用，不附加旧链接、错误占位或自动打开浏览器

#### Scenario: Unobservable copy origin
- **WHEN** 复制和首次观察之间已发生无法检测的切页，或网页以外的复制发生在 Chrome 前台期间
- **THEN** 首版不承诺精确归属；设置说明该限制，插入的来源可由用户检查、修改或删除

### Requirement: Bounded capture and stale result rejection

系统 SHALL 对剪贴板引用沿用最近一秒且每次复制最多引用一次的规则，以本次唤起开始时判断新鲜度，不因选区或来源等待延长时限；此时间窗不限制 `selected-text-capture` 的直接选区摘录。存在有效或已去重选区时 SHALL 抑制本次剪贴板候选及其来源，不在重开时补入；没有可用选区才回退本次唤起时符合条件且未被替换的复制。来源读取 SHALL 不阻塞主线程，与选区读取共用最多 150 ms 的额外等待预算，额度耗尽继续纯文字引用。确定本次草稿内容后 SHALL 不因迟到来源回调改写编辑区、已提交内容或已保存笔记。

#### Scenario: Slow source read
- **WHEN** 来源在本次唤起剩余的额外等待额度内未就绪
- **THEN** 继续展示可编辑引用，允许立即输入和提交；迟到结果不自动补写来源

#### Scenario: Reopen or stale copy
- **WHEN** 同一次复制已引用或因选区优先被抑制，或唤起开始时已超过原有新鲜度窗口
- **THEN** 重开面板不再次插入该剪贴板引用及来源，已有草稿仍保留；独立选区摘录按其自身规则判定

#### Scenario: Superseded panel preparation
- **WHEN** 等待来源时面板准备被取消、开始另一草稿或进入不接受引用的会话
- **THEN** 旧结果不能覆盖新会话、移动输入焦点或触发提交

#### Scenario: Selection has priority over cached attribution
- **WHEN** 当前选区为 A，近期复制为 B，且 B 已有 Chrome 来源
- **THEN** 本次只采用 A 的文字或抑制已采用的 A，不插入 B，也不把 B 的标题／链接附给 A

#### Scenario: Clipboard freshness is frozen before selection waiting
- **WHEN** 唤起开始时复制仍新鲜，但选区读取未成功且等待期间跨过一秒边界
- **THEN** 按唤起开始时的有效候选回退引用，来源只使用剩余预算；不从等待结束时重新计算或扩展新鲜度窗口

#### Scenario: Another copy replaces the fallback candidate
- **WHEN** 选区准备期间发生另一次复制，覆盖唤起开始时冻结的剪贴板版本
- **THEN** 不把后来的复制或旧候选来源作为本次回退输入，照常展示草稿；新复制留给下一次正常判定

### Requirement: Editable source in plain text draft

系统 SHALL 将来源作为引用后相邻的两行纯文字：本地化的“来源：标题”及独占一行的完整 URL，随后留出空行供输入想法。新增来源 SHALL 追加到对应引用，不覆盖已有草稿，不重排用户文字；输入与撤销沿用现有编辑器行为。系统 SHALL 不强制选择 Notes、不增加自动提交，也不将来源保存在独立隐藏附件中。

#### Scenario: Edit or remove attribution
- **WHEN** 用户删除来源、修正链接或手动附加源码路径后提交
- **THEN** 使用用户最终可见的草稿，不从旧快照恢复被删改的来源

#### Scenario: Multiple captures in one draft
- **WHEN** 用户先后引用两个网页片段到未提交草稿
- **THEN** 每个有效来源与自己的引用相邻保留，后一次不替换前一次来源

#### Scenario: Save failure recovery
- **WHEN** Notes 存入失败并触发既有恢复，或用户显式恢复单独保留的失败提交
- **THEN** 恢复提交时的文字、想法与来源，不重新读取当前浏览器；保留较新草稿的既有保护规则

### Requirement: Durable web links in Notes originals

系统 SHALL 在 Notes 新建和按天归集追加中将来源与想法作为完整原文保存；AI 关闭或补充失败不能删除来源。原文中独占一行的合法 HTTP/HTTPS URL SHALL 显式渲染为可点击链接，显示文字与纯文字表示保持原值，不解析其他 Markdown。生成区历史笔记来源 SHALL 继续使用既有规则，与本次网页来源分离。

#### Scenario: Ordinary save without AI
- **WHEN** 用户关闭 AI 和归集后将含来源的草稿存入 Notes
- **THEN** 标题、URL、引用与想法各按草稿保留一次；网页链接可点击并交由系统打开

#### Scenario: Grouped save and supplement refresh
- **WHEN** 带不同网页来源的提交追加到当天同一篇笔记，随后刷新 AI 补充
- **THEN** 各条完整原文及链接仍保留在各自条目内，不合并为一个全局来源或迁入生成区

#### Scenario: Safe rendering and readback
- **WHEN** 标题包含 HTML 特殊字符、URL 带查询参数与片段，或正文包含 Markdown 和代码
- **THEN** 特殊字符保持文字含义，合法独占行 URL 的链接目标与原文一致，其他正文不被解释为 HTML；原文回读与边界校验继续通过

#### Scenario: Source later unavailable
- **WHEN** 网页后来删除、需要登录或无法访问
- **THEN** 保留保存时的标题与链接，打开结果由浏览器处理，不替换为猜测地址或生成摘要

### Requirement: Independent transient source capture

系统 SHALL 仅为近期引用维护有界的内存来源状态，不新增网页历史数据库，不抓取正文或访问 URL；关闭剪贴板历史不影响已启用的来源功能。来自 Jotway 剪贴板历史恢复的自写内容 SHALL 不冒用当时 Chrome 页面作为新来源。标题、URL 与引用 SHALL 不额外写入诊断日志；进入草稿后的处理沿用现有内容规则。

#### Scenario: History disabled or restored
- **WHEN** 剪贴板历史关闭但来源已启用，或用户通过历史功能恢复一个旧片段
- **THEN** 前者仍可为新的 Chrome 复制附来源；后者不采集当前网页来补充旧片段

#### Scenario: Source expires or app exits
- **WHEN** 未采用来源过期、被新复制替代、关闭功能或退出应用
- **THEN** 清理对应内存状态，不为其创建可浏览的网页历史或重启恢复任务
