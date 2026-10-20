# selected-text-capture Specification

## Purpose

让用户划选外部应用中的文字后，直接使用既有全局快捷键带入快速记录面板并继续写想法。定义选区优先、权限、去重、可撤销编辑和失败降级的边界，避免复制时间窗、重复摘录与焦点切换破坏原草稿。

## Requirements

### Requirement: Existing shortcut captures the external selection before taking focus

系统 SHALL 在既有全局快捷键从外部应用打开隐藏的快捷输入面板时，于面板取得键盘焦点前读取该应用当前聚焦控件的选中文字。此输入 SHALL 不要求先复制，不受复制新鲜度限制，也不新增摘录快捷键。选区读取 SHALL 不改变系统剪贴板、发送模拟复制按键、读取整个控件正文或遍历其他窗口。

#### Scenario: Capture without copying
- **WHEN** 用户已授权辅助功能，在支持读取的外部 App 划选文字并停留超过一秒，然后按原唤起快捷键
- **THEN** 面板带入该选中文字的引用，光标可继续输入想法，系统剪贴板内容及版本不因摘录改变

#### Scenario: Existing visibility and protected editing rules
- **WHEN** 面板已可见（无论是否取得焦点），或处于临时便签、中文组词、action 配置或尚未完成受理的提交／应用启动转换
- **THEN** 沿用既有显示和保护行为，不借此读取外部选区、追加引用、打断组词或执行 action

#### Scenario: Open through another entry
- **WHEN** 用户通过菜单栏、Dock 或首次引导入口打开 Jotway
- **THEN** 不启动外部选区读取，沿用对应入口的既有草稿与剪贴板行为

### Requirement: Captured text is one editable quotation

系统 SHALL 将非空白选中文字逐行生成为纯文字 Markdown 引用，保留行内空白和中间空行，在已有草稿末尾以空行分隔追加并留出空行供输入。一次摘录 SHALL 构成一次原生可撤销编辑，保留既有正文、草稿身份和显式目标，不自动提交。首版 SHALL 仅插入文字，不为选区附加剪贴板来源或新读取的网页标题／链接；超过 1 MiB UTF-8 的选区 SHALL 整体放弃，不静默截断。

#### Scenario: Append and undo
- **WHEN** 草稿已包含想法和显式目标，用户成功摘录多行选中文字
- **THEN** 引用追加在末尾，正文和目标保留；一次撤销移除本次引用并恢复插入前选区，重做恢复引用但不执行 action

#### Scenario: Preserve plain text and source boundaries
- **WHEN** 选中文字包含空行、Markdown 或 HTML 字符，且此前 Chrome 复制具有缓存来源
- **THEN** 只按逐行引用保留文字，不执行 HTML、不改写为摘要、不拼接缓存来源；最终提交使用用户可见正文

#### Scenario: Oversized or whitespace-only selection
- **WHEN** 读取到超过上限或仅由空白构成的文字
- **THEN** 不插入截断内容或空引用，按无可用选区的规则继续打开面板

### Requirement: Reopening a draft does not repeatedly quote an adopted selection

系统 SHALL 在同一进程内按草稿身份记住已成功插入的可观测选区身份；来源、可用控件／范围身份及文字均相同时，隐藏后重开 SHALL 不重复追加，也不改用剪贴板重复补入。控件或范围身份不可用时 SHALL 按同一来源与相同文字保守去重。去重记录 SHALL 不跨新草稿或重启保留，未成功插入的读取不得标记为已采用。

#### Scenario: Hide reopen or remove the quotation
- **WHEN** 用户摘录后隐藏面板，或手动删除／撤销引用，再在相同来源与选区身份下重开同一草稿
- **THEN** 不重新追加该引用，不用同期剪贴板替代，用户修改继续保留

#### Scenario: A new draft or a different observable selection
- **WHEN** 用户开始新草稿后再次摘录相同文字，或在原草稿中摘录可区分的另一选区
- **THEN** 可追加本次引用，不因上一草稿的去重记录抑制

#### Scenario: Selection location cannot be distinguished
- **WHEN** 来源 App 不提供可区分的控件／范围身份，同一草稿再次读取同一来源的相同文字
- **THEN** 保守抑制重复，即使文字来自另一位置；不为判定位置而扫描其他内容

### Requirement: Unavailable capture preserves ordinary opening

系统 SHALL 区分无选区、不支持／不可用、权限不足、读取失败及等待超时；这些结果 SHALL 不阻止打开原草稿，沿用本次唤起时符合条件的既有近期剪贴板回退。有效或已去重的选区 SHALL 优先于剪贴板；同一次唤起不得同时插入两路引用。失败不得使用任意旧剪贴板、完整控件文字或上次选区冒充本次选区。

#### Scenario: Selection wins over a recent copy
- **WHEN** 当前选区为 A，系统剪贴板存在仍符合近期规则的 B
- **THEN** 仅带入 A，本次被抑制的复制不在重开时补入；之后新的外部复制仍可按原规则处理

#### Scenario: Unsupported control or missing permission
- **WHEN** 当前控件不支持选区读取、没有选区，或辅助功能权限不可用
- **THEN** 面板仍可编辑；只在原有一秒且每次复制最多一次的条件成立时回退剪贴板，不扩大该窗口

### Requirement: Preparation is bounded and stale results never alter a newer session

系统 SHALL 将外部选区读取及可能的剪贴板来源等待合并为最多 150 ms 的唤起额外等待预算，不在主线程同步等待外部应用。超时 SHALL 继续普通显示并使旧请求失效；草稿、编辑版本、来源应用或面板会话发生变化，以及用户取消时，旧结果 SHALL 不被采用。面板显示后不得因迟到结果追加文字、恢复焦点或触发执行。

#### Scenario: Slow or unresponsive source
- **WHEN** 来源应用读取缓慢，或已有读取仍未结束
- **THEN** 本次额外等待不超过总预算，用户可继续输入；不堆积无界后台读取，迟到结果被丢弃

#### Scenario: Source or draft changes during preparation
- **WHEN** 等待期间切到另一外部 App、取消唤起、开始另一草稿或修改当前正文
- **THEN** 本次选区结果失效，不把旧来源内容写入新草稿；原有编辑和显示选择不被异步回调覆盖

#### Scenario: Selection changes within the same source application
- **WHEN** 在等待预算内观测到来源 App 的聚焦控件或选区范围已改变
- **THEN** 放弃不一致的选区结果，不将旧文字与新位置拼成采用或去重身份；无法观测位置时仍遵循保守去重规则

### Requirement: Accessibility authorization is explicit and capture stays transient

系统 SHALL 在 General → Quick Entry 显示 Selected Text 权限状态、读取范围说明及主动授权／打开系统设置入口。系统授权请求 SHALL 仅由用户点击该入口触发；启动、后台检查及普通快捷键不得自动弹系统授权。未授权时面板 SHALL 提供非阻塞提示；授权或撤销后在下次唤起生效，不追补旧选区。未采用的文字及去重身份 SHALL 只在内存中存在，不写入历史、遥测或诊断；采用后的可见文字沿用草稿处理规则。

#### Scenario: First use denial and later grant
- **WHEN** 未授权用户按快捷键，随后主动请求授权、拒绝或在系统设置中允许
- **THEN** 原草稿一直可编辑，不反复弹窗；下次唤起按实际授权状态尝试摘录，不把授权前读到的内容补入正在编辑的草稿

#### Scenario: Authorization is revoked
- **WHEN** 用户撤销辅助功能权限，随后再次唤起
- **THEN** 设置状态反映不可用，面板按普通规则打开，既有 Notes／Chrome 功能不因缺少摘录权限被禁用

### Requirement: Permission status refreshes for the running application

Jotway SHALL 在设置页显示、设置窗口激活、设置可见时应用重新激活及用户点击“再次检查”时，被动刷新当前运行进程的辅助功能权限。有限重查 SHALL 在三秒内结束，不重叠运行刷新任务，也不请求授权。只有当前进程的成功 trust 检查 SHALL 显示权限可用。设置离开可见状态时 SHALL 取消待执行的重查。

#### Scenario: Return after granting access
- **WHEN** 用户在 macOS 开启辅助功能权限后返回 Jotway 设置
- **THEN** 设置重新检查；当前进程获信任时显示权限可用，下次符合条件的快捷键唤起尝试捕获选区，无需再次点击 Allow

#### Scenario: Delayed or unavailable access
- **WHEN** 从 macOS 设置返回后的首次被动检查仍为 false
- **THEN** Jotway 在有限窗口内重查，随后显示当前运行应用仍无法访问选中文字并提供恢复说明，不无限停留在检查中

#### Scenario: Access is revoked or checks overlap
- **WHEN** 权限被撤销后用户返回，或连续点击“再次检查”
- **THEN** 只有最新检查可发布结果；显示不可用状态，旧成功结果不能覆盖它

### Requirement: Unavailable permission has actionable recovery guidance

当前进程权限不可用时，设置 SHALL 准确描述该状态，不断言用户从未开启权限。设置 SHALL 保持“再次检查”、既有主动授权及系统设置入口可见；核对所打开 Jotway 副本的步骤、运行应用的位置及可用的临时路径提示 SHALL 放在默认折叠的 Troubleshoot Access 中，通过键盘可展开阅读。恢复说明 SHALL NOT 自动重置权限、移动应用、重启或丢弃草稿。

#### Scenario: User enabled permission but access remains unavailable
- **WHEN** 被动重查仍报告权限不可用
- **THEN** 设置显示当前运行应用仍无访问权限；展开排障说明可核对授权条目及运行副本后再检查，可选重启说明先提醒保存未保存的草稿，状态与授权按钮不因折叠而隐藏

#### Scenario: Running copy uses a temporary location
- **WHEN** 当前 Jotway bundle 位于 AppTranslocation 临时位置且权限不可用
- **THEN** 说明标明临时运行位置，建议先保存草稿再打开预期的已安装副本，不声称该路径证明故障原因，也不改变安装

#### Scenario: Authorization stays explicit
- **WHEN** 设置显示、执行被动刷新或点击“再次检查”
- **THEN** 不请求系统授权弹窗、不读取外部选中文字；Notes 与 Chrome 权限保持独立

### Requirement: Capture permission and browser capability remain distinct

每次符合条件的快捷键捕获 SHALL 独立重新检查当前进程权限。权限不可用结果 SHALL 更新共享权限状态；控件不支持、无选区、读取失败及超时 SHALL NOT 将权限标记为拒绝。确认授权 SHALL 只移除自有过期权限提示，保留其他错误。既有唤起、草稿、剪贴板及选区隐私规则 SHALL 保持有效。

#### Scenario: Granted access but unsupported webpage control
- **WHEN** 当前进程权限可用，但浏览器不提供选中文字
- **THEN** 设置继续显示权限可用，不引入权限拒绝提示，普通唤起遵循既有回退规则

#### Scenario: Successful capture after recovery
- **WHEN** 当前进程权限恢复，用户在支持的浏览器控件中划选文字，并以既有快捷键唤起隐藏的快捷输入面板
- **THEN** 新选区作为可撤销引用只追加一次，保留原草稿和目标，不重放旧选区

#### Scenario: Permission changes after Settings was checked
- **WHEN** 设置曾显示权限可用，而下次快捷键捕获观察到权限不可用
- **THEN** 共享状态更新为不可用，草稿按既有非阻塞提示及回退规则打开
