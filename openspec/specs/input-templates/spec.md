# input-templates Specification

## Purpose

让用户在快捷输入中通过模板快速形成可编辑草稿，并用编号占位符依次填写。此能力独立于 action 注册与执行，覆盖内置模板、自定义模板、本地保存、菜单回填及临时光标跳转，不新增持久化草稿或自动提交。

## Requirements

### Requirement: Two built-in templates are always available

系统 SHALL 默认提供“记录想法”和“梳理问题”，以稳定身份和固定顺序位于自定义模板之前；两者默认正文如下，用户可编辑名称和正文，但不能删除或改变其顺序。模板 SHALL 不绑定 action，不因 action 启用状态改变而隐藏。

#### Scenario: Insert the idea template
- **WHEN** 用户选择尚未修改的“记录想法”内置模板
- **THEN** 按以下模板展开，首先定位编号 1，填写顺序为 1、2、3，最后到 0

```text
想法：${1}

为什么值得做：${2}

下一步：${3}
${0}
```

#### Scenario: Insert the problem template
- **WHEN** 用户选择尚未修改的“梳理问题”内置模板
- **THEN** 按以下模板展开，首先定位编号 1，填写顺序为 1、2、3、4，最后到 0

```text
遇到的问题：${1}

预期结果：${2}

实际情况：${3}

已经尝试：${4}
${0}
```

### Requirement: Templates are managed independently in settings

Settings SHALL 提供独立的 Templates 页面，展示内置模板及自定义模板，支持内置项的名称与正文编辑，以及自定义项的新增、编辑和删除。每项只要求名称与多行纯文字正文；名称去首尾空白后非空、不含换行，并在全部模板中忽略大小写唯一。正文展开后 SHALL 包含非空白内容。新增及编辑表单 SHALL 纵向排列名称标签、单行名称输入框、正文标签和全宽多行正文输入框，标签、输入框及其下方的 Save 与 Cancel 均靠左。非法字段或占位符 SHALL 阻止保存并显示原因；取消编辑不得改变已保存项。

#### Scenario: Edit a built-in template without changing its identity
- **WHEN** 用户修改内置模板的名称和正文并保存
- **THEN** 设置列表与模板菜单使用新定义，身份及内置项前置顺序保持，不提供删除操作，不改写已经展开的草稿

#### Scenario: Keep stacked fields left-aligned
- **WHEN** 用户新增模板，或编辑内置或自定义模板
- **THEN** 名称与正文标签分别位于对应输入框上方，正文输入框占满可用宽度，标签、输入框及 Save 与 Cancel 靠左；取消后仍使用原已保存定义

#### Scenario: Create edit and delete a custom template
- **WHEN** 用户创建有效模板，修改其正文后保存，再删除该自定义项
- **THEN** 各次操作立即反映在模板列表；编辑保持该项身份与位置，删除只移除模板定义，不改写已展开草稿

#### Scenario: Reject invalid input without losing the saved version
- **WHEN** 用户提交空名称、重复名称、空白展开结果或不受支持的占位符
- **THEN** 明确指出问题，保留编辑内容和上一份有效版本，不报告保存成功

### Requirement: Template definitions persist locally without storing draft sessions

系统 SHALL 在本机保存自定义模板的身份、名称、正文与创建顺序，跨重启保留；新增项追加，删除后不自动重建。内置模板的名称与正文修改 SHALL 通过现有 `inputTemplates.v1` 的可选 `builtInOverrides` 保存，保留稳定身份与固定顺序，不以自定义项形式重复出现；未修改项使用内置默认定义，已有不含覆盖字段的自定义模板数据 SHALL 可继续读取。读取损坏或不兼容数据时 SHALL 保留原数据、显示问题并继续提供默认内置模板，禁用全部模板写入，不静默覆盖原存储；保存失败不得显示成功。定义持久化不包含用户填写结果或跳转会话。

#### Scenario: Restart after saving custom templates
- **WHEN** 用户保存多个自定义项后退出并重启
- **THEN** 内置模板只出现一次，自定义项及相对顺序保持，编辑器仍遵循既有空白草稿启动规则

#### Scenario: Restart with edited built-ins and existing custom data
- **WHEN** 用户在已有自定义模板的情况下编辑内置模板并重启
- **THEN** 内置项使用保存的名称与正文，身份与前置顺序保持；已有自定义项及其身份、相对顺序保持，不把内置项复制为自定义项

#### Scenario: Storage fails or cannot be decoded
- **WHEN** 保存失败，或启动时模板数据无法安全读取
- **THEN** 显示对应错误；保存失败保留上一份有效定义，读取失败保留原始数据、禁用模板写入并提供默认内置模板；不以空列表或默认定义回写，其他 action 不受影响

### Requirement: Leading at input opens a template-only picker

快捷输入 SHALL 在去除前导空白后的草稿为单行 `@` 加查询词时显示匹配模板，以名称做忽略大小写的包含匹配；空查询显示全部，顺序固定。列表 SHALL 不列 action。已填写正文中的 `@`、邮箱、临时便签、输入法组词中及活跃占位符填写期间 SHALL 不触发模板选择；无匹配时不拦截普通键盘或执行。

#### Scenario: Filter and choose a template
- **WHEN** 用户输入 `@`，再输入模板名称的一部分
- **THEN** 只显示匹配模板；新打开时高亮首项，Up／Down 和 Tab／Shift+Tab 可在列表中移动，Enter、Command+Enter 或点击选中项只请求回填一次

#### Scenario: Keep ordinary at text literal
- **WHEN** 用户输入邮箱、正文中的 `@`、含换行的草稿，或没有匹配模板的 `@codex 任务`
- **THEN** 不把文字作为 action 前缀处理，不出现无匹配菜单的专属键盘拦截；普通路由保持可用

#### Scenario: Dismiss or refresh an open picker
- **WHEN** 普通草稿中用户按 Esc 关闭列表，或设置中修改、删除当前候选
- **THEN** Esc 不改写正文，未改变文字前不自动重开；定义变化保留仍有效的高亮身份，否则选首个有效项，拒绝过期选择；不改写当前草稿

### Requirement: Template insertion is atomic editable and undoable

选中模板 SHALL 用展开正文替换整份 `@` 查询草稿，保留模板内换行与缩进，关闭列表并把焦点留在编辑器。回填 SHALL 是一次可撤销的原生文字编辑，保留既有显式目标，不执行 action、复制历史、启动配置、读取个人资料或发送业务 AI 请求。回填完成后的普通意图识别按既有策略处理；组词或状态变化导致无法替换时 SHALL 保持原文与原目标。

#### Scenario: Undo an insertion
- **WHEN** 用户选中模板后立即执行 Undo
- **THEN** 恢复填入前完整查询文字及选区，结束占位符会话；Redo 可恢复展开正文，但不恢复失效跳转状态

#### Scenario: Choose while another explicit target is retained
- **WHEN** 用户已通过目标菜单选择 Codex 或 Notes，随后选择模板
- **THEN** 显式目标保持；本次按键只填入，不启动任务或复制，后续仍需用户明确确认

#### Scenario: Refuse a stale insertion
- **WHEN** 候选出现后用户开始组词、切到便签、提交、启动配置或修改了查询
- **THEN** 过期选择不能覆盖草稿或移动光标，不产生部分回填或自动提交

### Requirement: Basic numbered placeholders expand into plain text

模板 SHALL 支持 `${n}` 和 `${n:默认文字}`，其中 n 为不带前导零的正整数，以及最多一个 `${0}` 作为最终位置。正编号按数值升序访问，可不连续且不得重复；默认文字展开并选中，空占位符只定位。标记 SHALL 不留在展开正文；无 0 时最终位置为正文末尾，无正编号时直接定位最终位置。首版不支持同编号联动、嵌套、变量、选择项或转换。

#### Scenario: Visit numbered positions rather than textual order
- **WHEN** 模板为 `先写 ${2:结果}，再写 ${1}。${0}`
- **THEN** 展开为 `先写 结果，再写 。`，首次定位编号 1；下一次选中“结果”，之后到句末并结束会话

#### Scenario: Use a template with one cursor or no placeholders
- **WHEN** 模板只有 `${0}` 或完全没有占位符
- **THEN** 分别定位指定位置或正文末尾，不进入 Tab 跳转会话，不消费原有焦点快捷键

#### Scenario: Reject unsupported syntax and permit literal markers
- **WHEN** 保存正文含重复编号、多个 `${0}`、`${0:文字}`、未闭合或不支持的 `${...}` 表达式
- **THEN** 拒绝保存并指出位置；用户以 `\$` 表示字面 `$`、以 `\\` 表示字面反斜杠，以 `\}` 在默认文字内表示字面右花括号；例如 `\${1}` 展开为普通 `${1}`，不建立占位符。简写 `$1` 作为普通文字保留

### Requirement: Placeholder navigation takes priority only during active filling

回填含正编号的模板后 SHALL 建立临时填写会话。Tab 前进、Shift+Tab 后退，首项后退停在首项；经过最后一项到最终位置时结束会话。Esc SHALL 只结束当前填写，不丢弃文字或关闭面板。会话结束后恢复原 Tab／Shift+Tab 和 Esc 行为；输入法组词始终优先。Enter／Command+Enter SHALL 继续既有明确确认语义，受理时结束填写；Shift+Enter 仍换行。

#### Scenario: Finish and restore focus shortcuts
- **WHEN** 用户从最后一个占位符按 Tab 到最终位置，再按 Tab 或 Shift+Tab
- **THEN** 最终位置不保留填写状态；后续按键沿用原有目标按钮或模式按钮焦点路径，不触发提交

#### Scenario: Escape before leaving a panel or conversation
- **WHEN** 填写会话活跃且未组词，用户按 Esc
- **THEN** 仅结束占位符跳转，正文保持；再次 Esc 才按普通草稿的原规则处理

#### Scenario: Compose Chinese or explicitly confirm
- **WHEN** 用户在占位符内组词，或组词结束后按 Enter／Command+Enter
- **THEN** 组词期间 Tab、Enter、Esc 不截断输入法；非组词的确认按当前目标及可用性检查执行，重复 Return 不重复提交；占位符跳转本身从不提交

### Requirement: Filling tracks edits and discards unsafe anchors

填写期间 SHALL 跟随当前字段内编辑、前方文字增删以及中文和 emoji 的实际位置更新跳转点。跨字段删除、移到当前字段之外、Undo／Redo、模式切换、面板隐藏、草稿替换或已受理提交 SHALL 结束会话并保留当前正文，不恢复旧光标。模板定义变化 SHALL 不修改已展开文字；普通识别刷新不得重建或重置会话。

#### Scenario: Expand a field before visiting a later field
- **WHEN** 用户将默认文字替换为更长的中英文及 emoji，再按 Tab
- **THEN** 定位更新后的下一字段，不落在组合字符或代理对中间，不覆盖字段外正文

#### Scenario: Leave the filling context
- **WHEN** 用户点击其他字段、跨字段删除、隐藏再打开面板、切到便签再返回，或恢复另一份草稿
- **THEN** 跳转会话结束，已编辑正文、正常选区及既有草稿保留策略继续生效，后续 Tab 不使用旧锚点

### Requirement: Templates and target-specific overlays share existing space

模板菜单 SHALL 复用现有下方有界区域，不叠加额外面板；打开时临时替代Clipboard 结果或 Codex 最近任务，关闭后恢复对应区域。菜单打开时 SHALL 阻止执行，保留显式目标及当前结果区域状态。辅助技术 SHALL 能读出模板名称、当前选择和字段跳转提示；模板管理及选择可用键盘完成。

#### Scenario: Insert a follow-up template without sending
- **WHEN** 显式 Codex 目标下用户输入 `@` 并选择模板
- **THEN** 菜单临时使用结果区域，回填后恢复最近任务；显式目标保持，已填任务未提交

#### Scenario: Insert into a local Clipboard query
- **WHEN** 当前目标为 Clipboard 时选择模板
- **THEN** 只把展开正文当本地查询，菜单确认不复制结果；查询和历史载荷仍遵循 Clipboard 的本地边界

### Requirement: Template picker uses text-first rows

模板选择菜单 SHALL 在标题处展示本地化的「输入模板」及一个单色图标，每个候选按名称在上、正文预览在下纵向排列，不重复行首图标。名称 SHALL 比预览更突出；两者各限一行，超长时尾部截断。高亮行 SHALL 使用整行背景和右侧回车提示，其余行保留提示占位，切换高亮不得移动文字。完整名称及预览 SHALL 可被辅助技术读取。

#### Scenario: Show built-in and custom candidates consistently
- **WHEN** 用户输入 `@`，列表包含内置模板及自定义模板
- **THEN** 菜单只有标题处显示统一图标；所有候选均显示上下两行文字，内置项和自定义项保持原有顺序，不增加类别徽标或额外配置字段

#### Scenario: Highlight and inspect a long candidate
- **WHEN** 用户用鼠标或既有键盘导航切换到名称、预览超过可用宽度的候选
- **THEN** 高亮背景与回车提示同步切换，文字位置和行高不变；两行文本尾部截断，悬停帮助可查看完整名称和预览，辅助技术可读出名称、预览及当前高亮状态

### Requirement: Template previews derive locally from expanded text

正文预览 SHALL 在本地按现有占位符规则展开，保留默认文字和转义后的字面内容，隐藏控制标记；去除每行首尾空白及行尾冒号，忽略空行，以 ` · ` 连接为单行文字。预览 SHALL 仅用于展示，不修改模板定义、草稿、光标或目标，不读取外部来源、不调用模型。展开失败或处理后为空时 SHALL 显示本地化的「无正文预览」，保留候选名称及既有选择校验。

#### Scenario: Preview the built-in idea template
- **WHEN** 菜单显示尚未修改的「记录想法」内置模板
- **THEN** 预览为「想法 · 为什么值得做 · 下一步」，不显示 `${1}`、`${2}`、`${3}` 或 `${0}` 控制标记

#### Scenario: Preserve defaults and escaped literals
- **WHEN** 自定义模板正文为 `主题：${1:周会}`、空行、`字面：\${2}` 和 `${0}` 组成的多行文字
- **THEN** 预览为「主题：周会 · 字面：${2}」，默认值和字面标记保留；真正回填仍使用原模板，保留其换行及占位符跳转

#### Scenario: Fall back without changing selection behavior
- **WHEN** 候选正文无法展开，或展开后只含空白及行尾冒号
- **THEN** 显示「无正文预览」而不隐藏候选或展示解析错误堆栈；浏览不改写草稿，确认仍通过既有定义及有效性校验

### Requirement: Text-first picker remains bounded and navigable

两行模板列表 SHALL 在既有悬浮层的可用高度内展示，标题与快捷键说明位于滚动列表之外；高度不足或超过最多六个可见候选时 SHALL 仅滚动候选区。键盘导航及候选刷新后，当前高亮项 SHALL 保持可见。模板专用说明 SHALL 明确回车只插入正文。不同目标下均 SHALL 使用同一布局与单一候选滚动区，保留原有历史及目标状态。

#### Scenario: Navigate beyond the visible candidates
- **WHEN** 候选超过六项，用户用 Up／Down 或 Tab／Shift+Tab 导航到可视范围外，再绕回首项
- **THEN** 列表滚动使高亮项可见，标题和快捷键说明保持可见；仅导航不执行回填或 action，窗口不超出既有可用高度

#### Scenario: Refresh candidates while scrolled
- **WHEN** 用户筛选名称或模板定义刷新导致候选内容、数量或高亮身份变化
- **THEN** 当前有效高亮项保持可见；失效身份沿用既有首项回退，预览反映最新定义，草稿及显式目标不变

#### Scenario: Open the picker with an explicit target
- **WHEN** 当前目标为 Codex 或 Clipboard，用户输入 `@`，再浏览并插入模板
- **THEN** 当前编辑器中的模板列表只有一个候选滚动区，菜单可完整导航；关闭后沿既有状态恢复相应历史区域，保留显式目标，本次确认只回填、不执行任务或复制

未受影响的触发条件、按名称筛选、Esc、中文组词、Undo／Redo 及回填合同继续遵循 [Current 产品说明](../../../docs/product/overview.md)与主规格中的既有要求。

### Requirement: Built-in template editing stays in the selected row

Templates 设置页 SHALL 在用户点击内置模板的 Edit 后，将该项原位置的只读内容替换为编辑表单，原处展示名称、正文、Save、Cancel 及本次保存错误，不在页面下方重复展示该项表单。成功保存或取消后 SHALL 在原位置恢复只读展示。表单布局、校验、内置身份及持久化继续遵循本能力已有要求；编辑过程 SHALL 只保留临时输入，成功保存前不改变有效模板定义。字段与操作 SHALL 可用键盘访问，支持 Command+S 保存和 Esc 取消。

#### Scenario: Begin editing either built-in in place
- **WHEN** 用户点击任一内置模板的 Edit
- **THEN** 只有选中模板的原卡片变为纵向编辑表单，填入其当前已保存的名称和正文，焦点进入名称输入框；另一内置项保持原顺序和只读展示，页面下方不再出现该项编辑副本

#### Scenario: Save and refresh the same built-in
- **WHEN** 用户在内置模板原地表单中提交有效修改，且保存成功
- **THEN** 表单在原位置收起并显示新名称和正文，模板菜单使用新定义，内置身份和前置顺序保持，不生成自定义副本，不改写已展开草稿

#### Scenario: Cancel an inline edit
- **WHEN** 用户修改内置模板输入后点击 Cancel 或在未组词时按 Esc
- **THEN** 丢弃本次未保存输入并在原卡片恢复已保存内容；模板菜单和本地保存值保持不变

#### Scenario: Correct a rejected inline save
- **WHEN** 内置模板的字段或占位符校验失败，或本地保存失败
- **THEN** 编辑表单仍在原卡片内，显示对应原因并保留当前输入及上一份有效定义，不显示保存成功；用户可继续修正重试或取消

#### Scenario: Keep read-only storage protection
- **WHEN** 模板数据读取损坏或不兼容，设置进入既有只读状态
- **THEN** 显示存储问题，内置模板 Edit 及全部写入操作禁用；默认内置模板仍可展示，不回写或覆盖原始数据

### Requirement: Template settings keep one pending edit at a time

Templates 设置页 SHALL 同时只允许一个新增或编辑会话；任何会话存在时，所有模板行的 Edit、Delete 及 Add 操作 SHALL 禁用，仅保留当前表单的 Save／Cancel，Save 继续遵循只读状态。不得删除正在编辑的项目或覆盖当前未保存输入。成功保存或取消后 SHALL 按现有只读状态恢复这些操作，保存失败时继续保护当前输入。自定义模板新增及编辑 SHALL 继续使用原有页面下方表单。

#### Scenario: Protect pending changes from another operation
- **WHEN** 用户正在编辑任一内置模板或自定义模板，或正在新增自定义模板
- **THEN** 所有模板行的 Edit、Delete 及 Add 不可触发，包括当前正在编辑的自定义项的 Delete，当前输入不会因切换目标而丢失；成功保存或取消后可开始下一次操作，保存失败则保持当前会话

#### Scenario: Keep custom editing in its existing area
- **WHEN** 当前没有编辑会话且模板可写，用户新增或编辑自定义模板
- **THEN** 仍在页面下方展示现有纵向表单，保持原保存和取消语义，不把该自定义项改为原地表单
