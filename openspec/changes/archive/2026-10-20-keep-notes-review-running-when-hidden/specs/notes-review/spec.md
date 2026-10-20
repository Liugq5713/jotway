## MODIFIED Requirements

### Requirement: One entry opens today with an optional weekly review

系统 SHALL 仅在快捷输入形态提供一个“今天回顾”图标按钮，外观遵循 `launcher-appearance`。每次从入口打开 SHALL 默认显示今天回顾的详情面板，按本机当前时区从今天零点筛选至请求时刻；面板内 SHALL 可切换今天回顾与周回顾。周回顾 SHALL 使用请求时刻向前滚动 7 天，不按自然周划分。系统 SHALL 不提供月回顾。Command+R SHALL NOT 打开、关闭或刷新回顾。

系统 SHALL 仅在 当前文本模型配置可用时启用回顾入口。未配置时保留入口并置灰，悬停及辅助功能提示先在 AI Services 配置 AI；配置失效时关闭当前回顾、取消生成并使缓存失效。

#### Scenario: Choose a review period
- **WHEN** 用户点击今天回顾按钮，或在详情面板内切换到周回顾
- **THEN** 输入区下方显示对应周期的回顾标题和日期范围，并立即为所选周期按需加载；有效完成缓存可直接复用，同周期有效请求正在运行时恢复其进度，不重复读取来源或调用模型；不执行草稿 action

### Requirement: Review navigation preserves the draft

查看回顾 SHALL 保留草稿、选区及显式目标。再次点击左下角入口 SHALL 关闭回顾；详情面板内选择另一周期 SHALL 切换回顾，选择当前周期 SHALL 保持展开；关闭按钮或 Esc SHALL 先关闭回顾，隐藏面板或切换形态 SHALL 清除打开状态。关闭回顾、隐藏面板、切换形态、编辑草稿或切换至其他下方详情 SHALL 仅清除展示状态，应用仍运行时已启动的回顾继续读取和生成。后台更新 SHALL 不重新打开面板或改写草稿。切换至不同周期 SHALL 取消旧周期请求并清除其临时预览及待发布更新；过期请求不得写入缓存或覆盖新周期。真正退出应用时结束进程内任务，不提供退出后执行或重启续跑。

#### Scenario: Switch and close a review
- **WHEN** 用户打开今天回顾后在详情面板选择周回顾，再点击左下角入口或按 Esc
- **THEN** 先取消今天的未完成请求并切换为最近 7 天回顾，再收起展示而保留周回顾生成；草稿正文、选区和目标保持不变

#### Scenario: Close during streaming
- **WHEN** 回顾已经显示预览，用户关闭、隐藏面板、切换形态或打开其他下方详情，随后旧请求继续返回
- **THEN** 清除界面中的预览，生成继续；后台进度不打开面板，完整有效结果可按现有规则进入缓存；再次打开同周期恢复有效任务的进度或展示有效完成缓存

### Requirement: Review reads authorized originals on demand

回顾 SHALL 使用独立的开关、Notes 权限及文件夹范围；已有自定义范围 SHALL 保留，不因移除 Related History 扩大范围。请求时 SHALL 通过公开 Notes 接口读取范围内元数据，按最近修改顺序最多读取 60 篇笔记的正文，每篇最多向文本模型提供 4,000 字符的已验证原文。生成区 SHALL 由既有边界记录排除。回顾 SHALL NOT 使用 embedding、持久化正文索引、后台同步或自动申请权限，也不修改 Notes 或草稿。

#### Scenario: Permission or model is unavailable
- **WHEN** 回顾功能开关已关闭、Notes 权限不可用或文本模型未配置
- **THEN** 显示相应不可用说明，不自动申请权限或发出模型请求

#### Scenario: Bounded source selection
- **WHEN** 范围内超过 60 篇近期笔记，或正文被截断、包含附件、无法读取或边界不清
- **THEN** 最多采用 60 篇中可验证的原文并说明覆盖限制；不以生成内容作为用户证据

#### Scenario: Failed reads are not empty successes
- **WHEN** 元数据或权限读取失败，或非空来源集没有任何可用原文
- **THEN** 显示失败，不缓存为没有笔记；只有成功读取到空来源集才能直接显示可缓存空结果

### Requirement: Period caches remain independent

今天及周回顾 SHALL 分别缓存最多 6 小时；今天回顾缓存仅在当前时区今天零点与缓存筛选起点相同时有效，跨自然日或改变日期边界后重新打开不得复用旧结果，不得将一个周期的结果用作另一个周期的结果。缓存 SHALL 仅收纳完整流成功且最终校验有效的摘要、合法空回顾或无来源确认的空结果，并绑定回顾范围／配置版本及 deep 模型链版本；预览、失败和取消不得写入或延长缓存。缓存复用 SHALL 保持当前权限与文件夹范围有效；切换范围、deep 配置或失去可用条件后不得展示不适用缓存。刷新按所选周期重新读取 Notes 原文，不创建索引。

#### Scenario: Reopen and switch periods
- **WHEN** 用户在缓存有效期内重新打开今天回顾，再在面板内选择周回顾
- **THEN** 今天回顾可复用其当日有效结果，周回顾独立加载或复用自己的有效结果，标题、日期范围和正文不混用

#### Scenario: Interrupted preview is not a cached review
- **WHEN** 回顾只收到预览便失败或被取消，用户随后重新打开同一周期
- **THEN** 该预览不能作为缓存复用；仍有效的更早完成缓存保持原时间，不存在完成缓存时重新生成

#### Scenario: Configuration or authorization becomes invalid
- **WHEN** 回顾正在前台展示、后台生成或已有完成缓存，而文件夹范围、deep 配置、回顾范围／配置版本、权限或启用条件改变
- **THEN** 撤销不再适用的展示与缓存，取消相关生成；仍打开的回顾给出重新生成或不可用状态，不自动扩大权限、启动后台扫描或请求新模型

#### Scenario: 隐藏期间完成后重开
- **WHEN** 用户隐藏面板后生成成功，并在同一天、同一有效配置及缓存期限内重新打开同周期回顾
- **THEN** 直接展示完整缓存，不因隐藏和重开重新读取来源或发起模型调用，后台完成不弹窗或抢焦点

#### Scenario: 隐藏期间失败后重开
- **WHEN** 隐藏期间请求失败或超时，用户随后重新打开同周期回顾
- **THEN** 失败预览不缓存，不在后台自动重试；此次主动打开按现有规则复用仍有效的旧完成缓存，否则重新生成，不停留在旧加载状态

#### Scenario: 跨日重开未完成的今天回顾
- **WHEN** 昨天启动的今天回顾仍在后台运行，用户跨本地自然日或改变时区日期边界后重新打开今天回顾
- **THEN** 不复用旧请求或预览，取消旧请求并按新的今天零点重新读取；旧请求的迟到结果不得覆盖新请求或污染缓存

### Requirement: Reviews show provisional readable progress

未命中缓存的今天／周回顾 SHALL 使用当前 deep 链流式生成，并在结束前逐步显示可安全解码的概述文字；主题及继续思考的问题 SHALL 只展示已完整收到且通过现有条目限制的内容。生成期间 SHALL 始终标识正在生成，日期范围、来源数量及覆盖限制依据本次请求的冻结资料显示。界面 SHALL 不显示原始 JSON、转义残片或思考过程，也不把预览标为已完成。布局 SHALL 沿用下方区域高度预算，不按片段改变窗口位置或尺寸、抢夺编辑焦点、修改选区或强制滚动。

#### Scenario: Read an overview before the stream ends
- **WHEN** 今天回顾或周回顾尚未结束，已收到概述的一部分和一个完整合法主题
- **THEN** 显示已解码的概述、该主题和生成中状态，后续内容继续更新；尚未收齐的主题或问题条目暂不展示

#### Scenario: Loading remains visible throughout generation
- **WHEN** 回顾正在读取来源或流式生成内容
- **THEN** 标题栏显示原生旋转加载动画和生成中文字；尚无可展示内容时，正文区域也显示加载动画和等待说明；出现部分内容后标题栏动画仍持续，完成、失败或取消后停止显示

#### Scenario: JSON escapes span fragments
- **WHEN** 中文、表情、引号、反斜线或 Unicode 转义跨多个片段到达
- **THEN** 只展示完整解码后的字符，不出现半个转义或损坏字符；最终结果仍通过完整业务校验

#### Scenario: A failed stream discards its preview
- **WHEN** 已有模型预览后请求失败
- **THEN** 清除临时内容并显示失败，不切换其他模型，也不缓存部分结果

#### Scenario: Navigate while progress arrives
- **WHEN** 用户在回顾生成过程中通过键盘导航或手动滚动回顾
- **THEN** 更新合并为有界频率，草稿、组词、选区、焦点及显式目标保持原有行为，滚动位置不被持续拉到末尾

#### Scenario: A draft change closes the review
- **WHEN** 草稿内容通过现有会话路径改变并触发关闭回顾
- **THEN** 收起回顾展示并继续已启动的生成，预览更新不重新打开回顾或改写新草稿
