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
