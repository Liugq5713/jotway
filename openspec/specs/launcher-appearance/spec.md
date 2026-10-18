# launcher-appearance Specification

## Purpose

定义快速记录面板在浅色和深色模式下的一致视觉语言，使输入正文、时间提示和目标入口具有清楚而克制的层次，同时保持紧凑结构、原生文字输入、可访问性和既有路由确认行为。

## Requirements

### Requirement: Appearance follows the system with a restrained surface

系统 SHALL 沿用现有 Follow System、Light、Dark 主题选择，在有效浅色外观使用不透明暖白卡面，在有效深色外观使用温润石墨灰卡面、低对比单条细边框及蓝灰控件。快捷输入、临时便签和已有下方卡片 SHALL 使用一致的卡面策略；深色且辅助设置允许时，在毛玻璃底层上覆盖约 95% 不透明度的卡面色，其他情况使用实色。材质 SHALL 限于各卡片圆角内部，不覆盖双卡间隙或降低正文、控件透明度。卡片内不得新增品牌标题、横向分隔线、独立底栏底色、纹理、厚边或额外外扩光晕；聚焦时仅输入卡内沿允许克制的流光，失焦或隐藏后停止并消失。

#### Scenario: Empty panel in either appearance
- **WHEN** 用户在浅色或深色模式下打开快捷输入的空草稿
- **THEN** 编辑区仅显示现有本地化占位文字和原生光标，底部动作行左侧保留 `temporary-draft-mode` 定义的模式入口，最近文档入口沿用本能力相应 requirement 的显隐与交互合同；动作行保留空间但没有目标入口或时间残留；卡片结构与该主题既有参考一致，图外状态标题和背景不进入应用

#### Scenario: Appearance changes during editing
- **WHEN** 面板可见且 Follow System 下的系统外观切换，或用户通过现有设置切换主题
- **THEN** 正文、占位文字、光标、边框、辅助文字和目标入口一起适配，卡面材质与正在显示的聚焦流光同步采用有效外观；正文、选区、中文组词、目标选择、菜单开闭状态和窗口尺寸保持不变，不重播流光入场

#### Scenario: Panel gains or loses focus
- **WHEN** 面板显示、重获焦点或失焦
- **THEN** 静态细边框保持可见；聚焦时可显示贴内沿的流光，深色使用低饱和灰雾蓝，稳态及入场峰值均减弱；重复输入和布局不重播入场，失焦或隐藏后停止动画并移除流光；既有进出窗口和提交反馈仍按原规则工作

#### Scenario: Dark cards over light and dark backgrounds
- **WHEN** 深色外观且辅助设置允许材质，用户将快捷输入或临时便签分别放在白色网页和黑色桌面上
- **THEN** 卡面保持深色石墨灰，只有背景层参与柔和混合，正文、占位文字、光标和控件仍清晰；不透出可辨认的背景文字，不要求两种背景呈现相同像素颜色，边框不形成亮灰白外圈

#### Scenario: Shared lower card keeps a transparent gap
- **WHEN** 深色面板打开任一既有下方菜单、预览或只读内容卡
- **THEN** 输入卡与下方卡采用相同材质及实色回退策略，各自按既有圆角裁剪，卡间间隙及圆角外保持透明；下方卡不新增流光，既有卡片尺寸、间距和交互不变

#### Scenario: Controls retain distinct visual states
- **WHEN** 深色目标胶囊的菜单打开或关闭，或用户聚焦目标及模式入口等现有控件
- **THEN** 普通、激活和键盘焦点状态仍可辨认，控件与新卡面保持柔和层次；浅色配色及所有目标选择、提交、显隐规则沿用当前相应规格

### Requirement: Typography and spacing preserve compact geometry

快捷输入形态 SHALL 保留 560 pt 默认宽、360 pt 最小宽、14 pt 圆角和 22 pt 固定动作行，将无屏幕约束时的初始及最小卡片高改为 122 pt，其中编辑区至少为 52 pt，容纳两行普通中英文。正文 SHALL 使用 16 pt 常规系统字体及 26 pt 基线间距，辅助文字维持 12 pt。正文与左下信息共享左对齐，首行及占位文字保持左上起笔，不因空白或单行状态垂直居中；新增空间 SHALL 属于可编辑区域，不由扩大内边距、增加栏位或插入空白字符形成。模式入口 SHALL 位于现有动作行左侧，不遮挡正文或改变快捷输入卡片高度，失败提示不得占用模式入口的预留位置；临时便签的独立几何遵循 `temporary-draft-mode`。

#### Scenario: Draft and preview change
- **WHEN** 自动高度的快捷输入从空白变为一行、时间摘要出现或消失、或用户清空草稿
- **THEN** 无屏幕约束时输入卡保持至少 122 pt，正文首行位置不变；动作行保留固定空间，目标按既有空白显隐规则呈现，目标右边缘和回车提示不因摘要显隐移动

#### Scenario: Narrow window and long content
- **WHEN** 窗口缩至 360 pt，出现长目标名、长时间摘要或多行正文
- **THEN** 目标与摘要不重叠，不缩小字体；长文字按现有规则截断并提供完整辅助说明，长正文在自动卡片高达到 360 pt 后内部滚动，底部操作保持可见

#### Scenario: Open an empty writing space
- **WHEN** 在空间充足的屏幕首次打开空草稿快捷输入
- **THEN** 默认输入卡为 560 × 122 pt，编辑区至少 52 pt，继续使用现有占位文案和原生光标，模式入口位于底部动作行左侧；不要求切换模式或手动拉高才能获得两行空间，草稿仍为空字符串

#### Scenario: Write within two ordinary lines
- **WHEN** 自动高度的快捷输入在默认宽度下输入一至两行普通中英文，且实际排版高度未超过 52 pt
- **THEN** 输入卡维持 122 pt，首行与光标遵循原生排版，后续行顺序占用预留编辑区，操作行不随每次换行下移

#### Scenario: Grow beyond the reserved space and delete back
- **WHEN** 自动高度正文排版超过 52 pt 后继续增长，再删除到短文或空白
- **THEN** 输入卡按实际排版向下增长至既有 360 pt 上限并保持顶边锚定，删除后按最新排版缩小至 122 pt；达到上限后正文内部滚动，不能因历史高度而持续占用旧空间

#### Scenario: Respect manual height and the independent sticky note
- **WHEN** 用户手动调整快捷输入高度，切换临时便签后返回，或重新唤起快捷输入
- **THEN** 手动高度仍按既有会话规则优先，空间充足时快捷输入不能缩至低于 122 pt；模式来回切换保留各自高度策略，重新唤起快捷输入恢复自动高度及新的最小值；临时便签仍以 300 × 200 pt 首次呈现、最小 240 × 160 pt，长文只在内部滚动

#### Scenario: Screen constraints override the preferred writing space
- **WHEN** 可用屏幕无法同时容纳两行编辑区、操作行及已打开的候选或 action 内容区
- **THEN** 系统优先收敛下方内容区，在仍不足时允许编辑区低于两行并内部滚动；窗口保持在可用屏幕内，模式入口及底部操作可达，不能为强保 122 pt 将操作挤到屏幕外

### Requirement: Target selector uses a lightweight capsule

系统 SHALL 在快捷输入形态中将普通非空草稿的目标呈现为浅底、无描边或立体效果的小胶囊，包含单色目标图标、目标名、轻分隔和回车提示；菜单打开时轻微加深，键盘焦点可辨认，鼠标悬停不增加反馈。胶囊 SHALL 保持可键盘聚焦；目标菜单关闭且草稿可确认时，鼠标点击整个胶囊 SHALL 沿用编辑区普通 Enter 的当前目标确认流程。分隔线和回车提示 SHALL 属于同一点击区域，不产生独立执行入口。空白草稿的显隐规则与胶囊几何 SHALL 保持不变；完整目标及鼠标确认、键盘选目标的区别 SHALL 可通过本地化帮助和辅助技术获知。

#### Scenario: Select a target through keyboard focus
- **WHEN** 用户用 Tab 聚焦胶囊后按 Return／Space
- **THEN** 打开现有目标菜单；菜单已打开时沿用现有高亮选择规则，选择只改变目标并返回编辑区、不提交草稿；Option+Up／Down 的 Notes/Codex 轮换继续可用

#### Scenario: Pointer interaction does not activate the capsule
- **WHEN** 用户仅悬停胶囊任意部位而没有点击
- **THEN** 不增加悬停反馈，不开关目标菜单、不切换目标、不提交草稿；完整目标和操作说明仍可通过既有帮助获知

#### Scenario: Confirm the displayed target with the pointer
- **WHEN** 目标菜单关闭、普通非空草稿可确认，用户点击胶囊的图标、名称、分隔线、回车提示或内部留白
- **THEN** 整个胶囊只产生一次当前目标确认，不打开菜单、不切换目标；后续受理、成功清理及应用启动结果与编辑区普通 Enter 一致，悬停不增加反馈

#### Scenario: Click while the target menu is open
- **WHEN** 目标菜单已打开，用户点击目标胶囊
- **THEN** 只收起菜单并返回原编辑位置，不采用仅高亮而未选中的目标，不提交草稿；菜单项目的既有鼠标选择仍只改变目标

#### Scenario: Explicit selection and action mentions
- **WHEN** 用户显式选择目标，或输入单行 `@` 查询打开模板菜单
- **THEN** 显式目标仍有可辨认标记且不推动布局；模板菜单期间只显示原回车提示，不提供目标胶囊点击确认，模板回填仍不执行；旧 action `@` 前缀按 `input-templates` 和 `launcher-action-routing` 保留为普通正文，左下模式入口保持独立

#### Scenario: Target changes or becomes unavailable
- **WHEN** 目标在内置 action、配置入口、本地应用或不可用目标之间变化
- **THEN** 图标与名称反映同一目标，不残留旧图标；缺少专属图标时使用一致的通用符号，不隐藏目标名称；点击沿用当前目标复核，不执行同次确认中新解析出的替代目标，不可用时保留草稿与显式选择并显示既有反馈

#### Scenario: Confirm a setup target
- **WHEN** 当前胶囊显示配置入口，用户点击胶囊
- **THEN** 按 Enter 的既有规则打开该配置流程并保留草稿；配置完成或取消后回到原草稿，完成配置本身不执行，仍需再次确认

#### Scenario: Composition and repeated clicks do not submit extra work
- **WHEN** 用户在中文组词期间点击胶囊，或一次确认仍在准备、等待受理或启动应用时再次点击
- **THEN** 组词不被点击强制结束、正文及选区保持且不提交；同一未完成确认不重复执行或排队重放，后续新的有效确认仍按既有会话规则处理

#### Scenario: Failed execution retains the draft
- **WHEN** 点击确认后准备被阻止或执行失败
- **THEN** 使用与 Enter 相同的失败提示及草稿恢复规则；已有新草稿时单独保留失败提交，不覆盖新输入，用户仍可修改后重新确认

#### Scenario: Reviewing does not confirm the draft
- **WHEN** 用户打开今天或周回顾后点击仍可见的目标胶囊
- **THEN** 与回顾期间的编辑区 Enter 一样，不提交、不启动配置或应用、不排队确认，保留回顾内容、草稿和目标

#### Scenario: Preserve hidden states and capsule geometry
- **WHEN** 草稿清空、切入临时便签、打开模板菜单，或窗口缩窄且目标名称变长
- **THEN** 空白及临时便签不出现目标胶囊或隐藏点击入口，模板菜单保留仅回填边界；其他状态保持既有胶囊高度、截断、右侧锚点和完整目标说明，不新增独立按钮或改变输入区几何

### Requirement: Recent saved document dots open read-only detail below the input

系统 SHALL 在两种形态的模式入口旁提供一个 22 × 22 pt 单色文档图标，按下述当天存入规则决定资格。无资格时移除入口、间距及辅助元素；有资格时按 `temporary-draft-mode` 悬停／焦点规则显现，隐藏仍保留宽度，选中有可辨认状态但不持续显现。入口 SHALL 提供本地化名称、帮助及原生键盘激活，组词时不得激活。仅成功 Notes 结果的有效 ID SHALL 更新最多三份去重引用，同 ID 移至首位；只持久化 ID 和确认时间，启动不扫描旧历史。

入口 SHALL 打开最新文档或关闭已有详情，按 ID 通过公开 Apple Events 异步读取 Notes 当前纯文字。下方只读卡最高 260 pt、受屏幕约束，正文内部滚动；区分加载、错误和成功，提供重试、关闭及下述导航。详情与 `draft-thinking-prompts` 互斥：打开详情失效提示并暂停自动追问，手动提示关闭并失效读取，详情关闭后按停写及关闭抑制规则重评。查看 SHALL 保留草稿、选区、插入点、Undo 和目标，不提交或修改文档。

#### Scenario: Use populated and empty document positions
- **WHEN** 最近成功存入文档为零至三份，或同一按天归集文档再次存入成功
- **THEN** 最多显示一个入口，其可用性由当天存入规则决定；同一 ID 只保留一个引用并移到首位，最多三个不同 ID 跨重启保留，不存储标题或正文，不生成空位控件

#### Scenario: Switch or close a live detail
- **WHEN** 用户激活文档入口，在下方切换文档，再次激活入口、关闭或按 Esc
- **THEN** 首次打开最新文档，面板内导航切换所选 ID，再次激活入口或关闭操作收起详情；Esc 先关闭详情再沿普通规则处理面板；关闭后重新打开仍从最新文档开始，不记住上次浏览位置

#### Scenario: Read without disrupting input
- **WHEN** 文档仍在读取、已删除或无权限，或用户正在中文组词
- **THEN** 保留草稿及原生编辑状态、目标；读取失败显示本地错误与重试，不用旧内容冒充成功；组词期间入口及详情操作不截断输入法，切换形态或隐藏面板关闭详情并使旧读取失效

#### Scenario: Exchange detail and thinking prompt
- **WHEN** 用户从正在读取的文档详情手动打开思考提示，或从提示打开最近文档
- **THEN** 仅显示最新选择的一份下方内容，旧读取或生成不能重新打开先前区域；草稿和目标不变，文档正文不传给提示模型

#### Scenario: Automatic prompting leaves document detail visible
- **WHEN** 自动追问已开启，用户打开最近文档详情，并在上方编辑区修改草稿后停止输入
- **THEN** 详情继续显示，不自动被提示替换；关闭详情后，仅对符合资格且尚未处理的最新正文重新等待约 1 秒再生成，文档正文仍不进入模型

### Requirement: One review icon shares the quick input footer

系统 SHALL 仅在快捷输入形态的左下动作行，在模式入口及当前可用的单个最近文档入口之后显示一个 22 × 22 pt 今天回顾图标按钮。本地化辅助名称及悬停说明 SHALL 为“今天回顾”，支持原生键盘聚焦和激活，不增高动作行或遮挡目标入口。左下图标 SHALL 使用统一的 22 pt 画布、1.25 pt 圆头圆角描边及 8 pt 按钮间距，回顾图标以日历外框中的单日表示。按钮沿用卡片悬停或键盘焦点显现规则，隐藏时保留宽度；任何周期的回顾打开时，此按钮 SHALL 保持可见并显示选中状态。每次打开默认今天，详情面板内可切换周回顾，不提供月回顾；周期、开闭与数据边界遵循 `notes-review`。

#### Scenario: Discover and activate the review
- **WHEN** 用户悬停快捷输入卡片或通过键盘进入左下动作行
- **THEN** 只有一个今天回顾入口可激活，中文组词期间激活不截断输入法；点击后展开今天回顾详情，可在面板内选择周回顾

#### Scenario: An open review remains discoverable
- **WHEN** 用户已打开今天或周回顾，再移开鼠标且键盘焦点离开按钮
- **THEN** 单个回顾按钮仍可见且保持选中，再次激活关闭详情；临时便签不显示回顾按钮

### Requirement: Visual refinement remains accessible and behavior neutral

系统 SHALL 保持清楚可读的文字、键盘焦点和现有完整辅助说明；增加对比度时优先可读性并加强边界，减少透明度或增加对比度时禁用卡面透射、使用不透明背景；减少动态效果时聚焦光 SHALL 保持静态，不播放位移、颜色循环或入场膨胀。辅助设置变化 SHALL 在当前面板生效，不重建编辑器或打断组词。快捷输入的外观变化不得修改纯文字、中文组词、路由、时间计划确认或失败恢复语义，目标确认入口及其保护条件继续遵循相应行为规格；临时便签的明确编辑差异遵循 `temporary-draft-mode`；时间区域继续遵循 `launcher-schedule-preview`。

#### Scenario: Accessibility settings are enabled
- **WHEN** 用户启用增加对比度、减少透明度或减少动态效果
- **THEN** 文字与焦点仍可区分、边界得到适当加强且无闪烁，装饰性图标、材质和分隔线不成为额外 VoiceOver 元素；减少透明度或增加对比度时各卡面为实色，减少动态效果时停止持续动画、只保留静态聚焦光，单独减少透明度不强制停止流光运动

#### Scenario: Input and failure recovery remain intact
- **WHEN** 用户在快捷输入中进行中文组词并按 Enter、插入换行、确认时间计划或遇到提交失败
- **THEN** 输入法、快捷键、计划展示确认与草稿恢复沿用现有规则；目标确认沿用已生效的目标交互规格及其组词保护，材质与流光不增删执行、清空或切换目标的入口

#### Scenario: Accessibility preferences change while writing
- **WHEN** 用户在面板显示期间开关减少透明度、增加对比度或减少动态效果
- **THEN** 卡面、边界和聚焦光及时遵循最新设置，关闭后恢复当前有效主题允许的效果；正文、选区、插入点、撤销历史、目标与窗口几何不变，不重播流光入场

#### Scenario: Submission snapshot uses a safe card surface
- **WHEN** 启用深色材质后用户提交，既有退场效果需要使用面板快照
- **THEN** 快照仅包含应用自身内容；材质无法捕获时使用同主题不透明卡面填底，文字、圆角及透明双卡间隙完整，不闪现系统浅色底或出现透明碎片；不通过截取其他应用或屏幕补齐材质，无法取得可用自身快照时沿用已有关闭回退

### Requirement: Automatic quick input height follows the current draft

快捷输入处于自动高度模式时，系统 SHALL 根据当前草稿的实际排版让编辑区、输入卡及窗口双向调整高度。删除、替换、粘贴及撤销重做引起的正文缩短 SHALL 与新增正文一样刷新几何，无需额外输入或重新唤起。保留 122 pt 输入卡下限、360 pt 自动高度上限、290 pt 编辑区上限及既有屏幕约束；未触及屏幕边界时保持窗口顶边锚定。

#### Scenario: Delete the line break that grew the card
- **WHEN** 无悬浮层的快捷输入未手动调整高度，用户在末尾含两个换行的正文中再插入一个换行，待输入卡增高后退格删除该换行
- **THEN** 本轮排版及尺寸回调完成后，编辑区、输入卡和窗口均恢复到插入前的高度，误差不超过 1 pt；不需要再输入、撤销、失焦或收起重开

#### Scenario: Remove successive trailing line breaks
- **WHEN** 用户逐次删除多行草稿末尾的换行，直至仅剩一行正文或清空草稿
- **THEN** 每次删除后高度均由剩余正文决定；达到最小高度后保持 122 pt 输入卡，动作行完整可见，不保留已经删除的空行空间

#### Scenario: Shorten text after reaching the scrolling limit
- **WHEN** 自动高度的长草稿已达到滚动上限，用户删除或替换正文，使剩余排版高度低于上限
- **THEN** 输入卡和窗口重新按剩余正文收缩；末行及高字形可完整滚入可见区域，不因旧文档高度留下额外滚动空白

#### Scenario: Paste and undo use the same sizing behavior
- **WHEN** 用户粘贴多行纯文字，再通过选区替换、撤销或重做使草稿变短或恢复
- **THEN** 各操作完成后高度均与直接编辑到相同正文时一致，同时保留正文、选区和可用撤销历史，不执行 action

### Requirement: Geometry updates preserve the latest editing policy

系统 SHALL 以最新正文、编辑宽度、形态及高度策略对应的排版结果更新几何；过期回调不得恢复旧正文高度。自动伸缩不得把窗口标记为用户手动调整。用户手动高度优先及临时便签固定窗口、模式间独立几何继续遵循 Current 文档与 `temporary-draft-mode`。

#### Scenario: Settle rapid edits at the latest layout
- **WHEN** 用户连续输入、删除或改变编辑宽度，多个尺寸更新尚在等待完成
- **THEN** 回调稳定后的高度与最终正文和宽度一致；稍早的大高度不得使已经缩小的窗口再次增高，不出现持续往复伸缩

#### Scenario: Respect a manually chosen quick input height
- **WHEN** 用户手动调整快捷输入窗口高度后输入或删除多行正文
- **THEN** 窗口沿用手动高度和现有屏幕约束，正文在可用区域内滚动；按既有规则重新唤起并恢复自动模式后，最新正文的伸缩再次生效

#### Scenario: Ignore obsolete updates across mode changes
- **WHEN** 快捷输入的尺寸更新尚未完成，用户切到临时便签并编辑正文，再切回快捷输入
- **THEN** 临时便签不被旧回调自动伸缩；切回后使用最新正文及该形态保存的高度策略，不恢复过期高度，正文和选区按既有模式切换规则保留

### Requirement: Recent document entry requires a confirmed save today

最近文档入口 SHALL 仅在保留的文档引用中至少有一次存入确认时间落在本机当前时区的今天自然日时可用。只编辑草稿、开始存入或存入失败 SHALL 不满足条件；新建及追加已有文档的成功确认均满足。条件 SHALL 只控制入口，不清除旧引用、不把导航限制为当天文档。打开、重新唤起、存入确认、跨午夜、系统日期或时区变化后 SHALL 重新评估；失去条件时隐藏入口并关闭已打开的文档详情，使旧读取失效，不修改草稿或强制结束组词。

#### Scenario: Older documents do not reveal the entry
- **WHEN** 本机保留一至三份昨天或更早的文档引用，今天尚无成功存入
- **THEN** 两种形态均不显示最近文档入口或额外间距，键盘及辅助技术不能聚焦该入口；旧引用继续保留，不通过扫描 Notes 决定显隐

#### Scenario: The first confirmed save reveals the entry
- **WHEN** 今天首次新建或追加 Notes 文档成功，并返回有效文档 ID
- **THEN** 入口取得可用资格，并按卡片悬停／键盘焦点规则显现；点击打开最新文档，之后仍可导航到保留的较早日期文档

#### Scenario: Draft editing and failed saves do not qualify
- **WHEN** 用户今天仅编辑草稿、尝试存入但失败，或成功结果不含有效文档 ID
- **THEN** 不因此显示入口，不记录一次可用的当天存入

#### Scenario: Reevaluate at midnight and after time changes
- **WHEN** 面板可见或应用重新活跃，今天自然日因午夜、系统日期或时区变化而改变
- **THEN** 按新的本机自然日重新判断；若不再有当天确认则关闭详情并隐藏入口，迟到读取不能重开；重新唤起或重启也按当前日期及已有引用判断，不恢复旧详情

### Requirement: Recent documents are navigated inside the lower detail panel

详情面板 SHALL 显示当前位置／总数，使用最近确认至最早确认的顺序；多于一份时在面板内提供上一条和下一条，分别选择更新及更早的相邻文档，到边界禁用且不循环；仅一份时隐藏两按钮。加载及错误状态 SHALL 仍允许可用方向切换；每次切换清除上一份正文、错误与滚动位置，并拒绝所有旧成功或失败结果。导航 SHALL 支持本地化、原生键盘与辅助技术且保护组词，不绑定编辑器方向键；异步完成不抢焦点或反复改变窗口几何。

#### Scenario: Traverse three documents without wrapping
- **WHEN** 有三份引用，用户打开入口并依次选择下一条、下一条、上一条
- **THEN** 位置依次为 1 / 3、2 / 3、3 / 3、2 / 3，内容及存入时间对应所选文档；首份的上一条及末份的下一条禁用，边界激活不读取或循环

#### Scenario: One document needs no navigation controls
- **WHEN** 当天条件满足且只保留一份引用
- **THEN** 显示 1 / 1，隐藏上一条和下一条，仍可重试或关闭，不出现空白导航占位

#### Scenario: Keyboard navigation reaches a disabled endpoint
- **WHEN** 用户通过键盘选择上一条或下一条，到达边界后当前按钮变为禁用
- **THEN** 焦点仍能沿可用命令返回编辑区，不困在禁用按钮上；边界不循环、不提交草稿，原编辑区选区保持

#### Scenario: Switch while a read is pending or failed
- **WHEN** 用户从仍在加载或读取失败的文档切到相邻文档，之后旧请求成功或失败
- **THEN** 立即显示新文档的位置、时间和加载状态，不残留旧正文；只接受新选择的请求结果，重试只重读当前文档，不阻止其他可用方向的切换

#### Scenario: Preserve document identity when references change
- **WHEN** 详情打开期间成功存入使引用重新排序、去重或淘汰最早一份
- **THEN** 按文档 ID 保留仍存在的选择并更新位置／总数；同一选中文档再次存入时重新读取当前正文，所选 ID 被淘汰时关闭详情，下次从最新文档打开，不把相同位置的新 ID 当成旧选择

#### Scenario: Navigate in a narrow writing panel
- **WHEN** 用户在 360 pt 快捷输入或 240 pt 临时便签宽度内，通过鼠标、键盘或辅助技术操作导航与关闭
- **THEN** 位置、导航和关闭保持可达，必要时缩短或隐藏时间文字并提供完整辅助说明；切换保留写作卡及用户最新拖动／缩放选择，异步返回不移动焦点，草稿、选区、Undo、目标及 Enter 规则不变
