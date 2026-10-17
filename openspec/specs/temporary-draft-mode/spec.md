# temporary-draft-mode Specification

## Purpose

允许用户把快速记录面板中的同一份草稿切换为本次工作期间使用的置顶临时便签，兼顾旁置阅读、多行编辑和回到快捷输入执行 action。定义模式入口、窗口形态与临时生命周期，确保既有输入布局和正文不会因模式切换被破坏。

## Requirements

### Requirement: Mode control stays at the bottom-left outside the editor

系统 SHALL 在快捷输入和临时便签两种形态的底部 22 pt 操作行左侧提供一个小型模式图标，显隐遵循下述交互规则；图标与其点击区域均不得进入编辑区。当前可用的单个最近存入文档入口 SHALL 紧邻模式入口，`draft-thinking-prompts` 的思考提示按钮 SHALL 位于最近文档入口之后、该入口不可用时收拢；快捷输入的目标胶囊 SHALL 保持在同一行右侧，已有回顾入口的位置遵循 `launcher-appearance`。失败提示 SHALL 从当前所有底部控件的预留位置之后开始，即使可用图标暂时隐藏也不得占用该位置。快捷输入的卡片高度与间距 SHALL 保持不变；临时便签 SHALL 在既有窗口尺寸内为操作行预留空间，仅收敛编辑区视口。该入口 SHALL 不增加顶栏、正文缩进、换行避让区或拖动图标。

#### Scenario: Render the control below an ordinary draft
- **WHEN** 快捷输入显示非空草稿及右下目标胶囊，且用户将鼠标移入输入卡片
- **THEN** 模式图标位于底部操作行左侧，目标胶囊位于右侧，二者与正文不重叠；快捷输入正文、行距、编辑宽度、卡片高度和操作行位置保持不变

#### Scenario: Target capsule is absent or changes width
- **WHEN** 草稿为空、模板菜单暂时阻止目标选择，或目标名称变长
- **THEN** 模式图标沿用相同显隐规则和同一左下锚点，不随目标名称长度或胶囊显隐移动；其位置始终保留，失败提示不进入该位置；旧 action 前缀不再隐藏目标标签

#### Scenario: Long text and narrow windows
- **WHEN** 用户输入多行文字、选中首行末尾文字、缩窄窗口或滚动正文
- **THEN** 正文和选择区域均不被图标或其点击区域遮挡；首行末尾仍可编辑，图标留在左下操作行而不随正文滚动；便签编辑区视口为该行预留空间且窗口尺寸不变

#### Scenario: Reserve the thinking prompt entry
- **WHEN** 用户在任一形态查看底部操作行，最近文档资格或数量变化，或出现失败提示
- **THEN** 模式、当前可用的单个最近文档入口及其后已有回顾／思考入口各自有界占位；文档由一份变成三份不增加入口宽度，无当天存入则移除其位置及间距，反馈不侵入剩余控件

### Requirement: Footer controls appear on card hover or keyboard focus

模式及当前可用的单个最近文档入口 SHALL 使用默认隐藏的 22 × 22 pt 控件。模式图标约 12 pt、圆角线条：快捷输入为折角便签，便签为含光标和文字线的输入窗，无常驻底座或外框。模式按钮 hover SHALL 呈柔和蓝灰底色、6 pt 圆角、细边、提亮图形及手形光标；按下增强背景约 100 ms、不移动缩放；键盘焦点用强调色轮廓。

进入整张卡片 SHALL 弱化显示可用入口，hover 具体控件时强调。自身 hover 或键盘焦点保持可见，文档选中不保持可见；离开卡片且无 hover／焦点时约 120 ms 淡出，减少动态效果时直接隐藏。显隐 SHALL 只改绘制透明度，不改几何、推动布局或移除原生按钮、提示及焦点入口。文档不满足 `launcher-appearance` 当天存入条件时 SHALL 移除整个入口、间距、焦点及辅助元素；有资格始终只保留一个控件。系统 SHALL 提供本地化名称、提示及键盘激活，增加对比度时优先保证显示状态可辨认。

#### Scenario: Reveal from anywhere in the card
- **WHEN** 鼠标从卡片外进入输入卡片的正文、留白或底部操作区
- **THEN** 模式入口与当前可用的最近文档入口以弱化颜色显示，不要求用户先找到隐藏按钮；鼠标进一步进入模式按钮时出现柔和底色与更清楚的图形，并提示当前可执行的切换方向

#### Scenario: Leave and re-enter the card
- **WHEN** 鼠标移出输入卡片，且按钮没有键盘焦点
- **THEN** 未悬停且无键盘焦点的控件淡出，最近文档选中本身不阻止淡出；淡出期间重新进入卡片立即恢复显示，正文及可用控件的占位始终不变；启用减少动态效果时直接隐藏

#### Scenario: Move onto the button and read its tooltip
- **WHEN** 鼠标由卡片正文移到模式按钮并停留阅读原生提示
- **THEN** 图标保持显示，原生按钮和提示不会因为显隐动画被移除或失去命中区域

#### Scenario: A mode switch moves the footer controls
- **WHEN** 用户点击模式切换后，窗口尺寸或控件位置改变，随后将鼠标移出输入卡片，且控件没有键盘焦点
- **THEN** 模式入口与可用的最近文档入口按当前鼠标位置淡出；跟踪区域重建前的悬停状态不得使控件常驻

#### Scenario: Keyboard and accessibility operation
- **WHEN** 没有活跃模板填写或模板菜单时，用户从编辑器以 Shift+Tab 聚焦隐藏的模式按钮，或通过既有键盘路径聚焦按钮
- **THEN** 图标显示并提亮，鼠标在卡片外时也保持可见；Return 或 Space 只激活对应控件、不提交草稿；最近文档只有一个底部焦点，并可经键盘进入下方详情命令；辅助技术读出对应名称；活跃模板填写时 Shift+Tab 优先返回上一字段，结束填写后恢复本入口

#### Scenario: An entry loses its current-day eligibility
- **WHEN** 最近文档入口或详情命令拥有键盘焦点，日期变化使当天存入条件不再满足
- **THEN** 移除入口并关闭详情后将焦点安全返回编辑区，不残留不可见焦点；原编辑区已在组词时不改变其焦点或结束组词

### Requirement: Mode changes preserve a single temporary draft

系统 SHALL 在同一个快速记录面板内切换快捷输入与临时便签，复用一份草稿，保留正文、选区、插入点、撤销历史和显式目标选择。切换 SHALL 关闭最近存入文档详情与思考提示，并使未完成读取或生成失效，不执行 action、不新建笔记、不读取或追加剪贴板、不把草稿标记为已提交；未变更正文的切换 SHALL 不产生新的正文版本。

#### Scenario: Switch back after editing
- **WHEN** 用户切到便签后修改正文、选中文字，再切回快捷输入
- **THEN** 快捷输入包含完整修改结果并保留当前选区，可撤销便签中的编辑；目标按最新正文与既有显式选择重新解析，仍需用户确认才能执行

#### Scenario: Switch while a routing menu or preview is present
- **WHEN** 普通草稿的候选菜单、`@` 补全、Clipboard 结果、Codex 最近任务或时间预览正在显示，用户切到便签
- **THEN** 这些辅助区域收起，正文不变；旧预览不保留执行资格，切回后重新计算并按既有规则确认

#### Scenario: Switch with a prompt in progress
- **WHEN** 提示显示或生成中，用户切换形态
- **THEN** 关闭提示并清理计时、候选及生成，草稿及原生编辑状态不变，旧响应不改变窗口高度；自动追问关闭时不自动请求，开启时依 `draft-thinking-prompts` 的资格和停写规则重新评估，不恢复旧提示或绕过用户关闭抑制

### Requirement: Sticky mode edits without executing actions

临时便签 SHALL 呈现草稿编辑区与底部操作行左侧的返回入口、当前可用的单个最近文档入口与思考提示入口，并可在输入区下方互斥显示所选文档的只读详情或 `draft-thinking-prompts` 定义的临时思考提示；最近文档的当天条件及面板内前后导航遵循 `launcher-appearance`。隐藏 action 目标、失败提示及候选、执行预览区域。Enter 和 Shift+Enter SHALL 插入换行，Command+Enter SHALL 不执行、不清空、不排队提交。普通 Tab SHALL 按原生编辑处理，最近文档入口及详情命令继续支持原生键盘焦点，`@` SHALL 保留为正文而不触发补全；执行 action 必须先返回快捷输入。中文组词与原生复制、粘贴、撤销仍优先。

#### Scenario: Write multiple lines including an action mention
- **WHEN** 用户在便签输入 `@notes` 开头的多行正文，按 Enter、Shift+Enter 或 Command+Enter
- **THEN** Enter／Shift+Enter 正常换行，Command+Enter 不改变草稿或执行 action，不出现目标或补全菜单

#### Scenario: Return to normal execution
- **WHEN** 用户切回快捷输入后按 Enter
- **THEN** 沿用快捷输入的显式目标、识别、配置、计划确认和失败恢复规则；切换本身不视为确认

#### Scenario: Write while a thinking prompt is shown
- **WHEN** 用户在便签手动取得思考提示，或自动追问开启后在停写时取得提示，随后在编辑区继续写作
- **THEN** 提示在下方显示，自动关闭时保持原提示，开启时按停写规则更新；Enter／Shift+Enter 继续换行，Command+Enter 不提交，结果不插入正文、不创建笔记或改变目标

### Requirement: Sticky geometry is independent within the current run

临时便签首次 SHALL 为 `300 × 200 pt`，维持横向初始比例，默认浮于普通应用窗口上方、失焦仍显示；用户 SHALL 可沿用现有拖动与缩放。两种形态 SHALL 在本次运行分别保留窗口位置与尺寸，便签正文增长时内部滚动而不自动长高。屏幕约束 SHALL 优先于保存的几何，保证窗口可找回。

#### Scenario: First switch and repeated switching
- **WHEN** 用户首次切到便签，拖到一旁并缩放，然后来回切换
- **THEN** 首次以原窗口左上角为锚点改为 300 × 200 pt，必要时收敛到当前屏幕；以后在当前屏幕恢复各模式尺寸，仅当保存位置属于当前屏幕时恢复该位置；快捷输入恢复进入便签前的手动或自动高度策略

#### Scenario: Switch after moving to another screen
- **WHEN** 目标模式保存的位置属于 A 屏，当前窗口已经在 B 屏，用户点击模式切换
- **THEN** 窗口保持在 B 屏，只恢复目标模式的尺寸，并以当前窗口左上角为锚点在 B 屏可用范围内收敛；不得因恢复 A 屏的旧位置而跳屏

#### Scenario: Read while working in another app
- **WHEN** 用户点击另一个普通应用窗口并继续工作
- **THEN** 便签保留正文与窗口位置、保持可见，不抢回键盘焦点；用户调整便签后，长正文仅在编辑区内滚动

#### Scenario: Saved screen becomes unavailable
- **WHEN** 原显示器断开或可用屏幕范围不足以容纳保存的位置和尺寸
- **THEN** 恢复到可用屏幕并收敛越界部分，模式入口和正文可操作；便签不因沿用快捷输入最小宽度而被强制放大为 360 pt

#### Scenario: Show and close a recent document below sticky input
- **WHEN** 用户在便签打开最近存入文档详情，然后关闭详情
- **THEN** 打开时保留写作卡的手动高度，在下方增加有界可滚动详情并遵循屏幕约束；关闭时恢复打开前受屏幕约束的窗口框架，期间用户主动移动或缩放则以其最新选择为准；草稿、选区及目标不变

### Requirement: Hiding keeps the temporary draft and restarting clears it

便签 SHALL 沿用普通草稿的进程内保留边界：最近存入文档详情或思考提示打开时 Esc SHALL 先关闭当前下方区域；Esc 或全局快捷键收起面板时保留草稿和当前模式，再唤起恢复，但不恢复详情或思考提示；隐藏 SHALL 清除提示、计时及候选并使未完成生成失效。再唤起 SHALL 仅按 `draft-thinking-prompts` 的偏好、保护及关闭抑制规则决定是否建立新请求。退出、崩溃或重启后 SHALL 回到空白快捷输入，不自动恢复便签正文、模式或便签几何。既有本地操作记录采样及快捷输入位置偏好 SHALL 保持原有策略，临时便签不新增持久化草稿；最多三份文档 ID 与存入时间的引用独立保留。

#### Scenario: Hide and reopen
- **WHEN** 用户在非组词状态按 Esc 或用全局快捷键隐藏便签，再次唤起
- **THEN** 恢复便签和原草稿，保留便签的会话内几何，不额外自动追加剪贴板或浏览器引用

#### Scenario: Restart after temporary editing
- **WHEN** 应用退出或崩溃后重新启动
- **THEN** 显示空白快捷输入；本地操作记录即使包含旧正文，也不用于恢复便签

#### Scenario: Hide with an unfinished prompt
- **WHEN** 用户在提示生成中隐藏面板，随后重新唤起，或退出并重启应用
- **THEN** 旧生成不能重新显示；再唤起沿用原草稿，自动关闭时不请求，开启时仅按当前资格与停写规则建立新请求；重启仍为空白快捷输入，只恢复布尔偏好而不恢复提示或草稿

### Requirement: Unsafe transitions do not disturb active work

系统 SHALL 在中文组词期间阻止任一方向的模式切换；首次引导、action 配置、Personal Agent 活跃会话及尚未完成受理的提交／应用启动转换期间 SHALL 阻止切到便签，并提供简短原因；不得以切换为由取消会话或提交。切换后过期的识别、预览及尺寸回调 SHALL 不恢复隐藏的辅助区域、不改变便签尺寸、不覆盖新草稿。

#### Scenario: Attempt a blocked switch
- **WHEN** 上述任一受保护状态下用户尝试切换模式
- **THEN** 模式和当前工作保持不变，中文组词不被强制提交，按钮说明暂不可切换的原因；恢复可切换状态后无需重启

#### Scenario: Late result after switching
- **WHEN** 用户切到便签后，旧的识别、内容尺寸或预览结果返回，或之前的后台 action 报告失败
- **THEN** 便签不跳回快捷输入、不弹出候选或自动缩放；失败仍按既有草稿冲突保护保留，可在切回后恢复，不能覆盖已编辑的新草稿
