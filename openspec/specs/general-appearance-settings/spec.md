# general-appearance-settings Specification

## Purpose

定义 General 与 Appearance 的设置归属和浏览顺序，以及设置页说明的展示层级，让用户能找到控制项；整理页面时保留已保存选择、必要的隐私／权限／删除说明、错误提示与键盘可达性。

## Requirements

### Requirement: Appearance owns theme and finish animation

Appearance SHALL 按 Color Theme、Input Background、Finish Animation 的顺序展示主题与动画设置；General SHALL 不再包含动画选择。主题卡 SHALL 显示名称和选中状态，不重复解释浅色／深色，不显示立即生效或自动保存的常驻说明。Finish Animation SHALL 只展示一次标签；主题说明和减少动态效果说明 SHALL 保留在悬停及辅助功能帮助中，不要求重复的页面副标题。

#### Scenario: Find visual preferences
- **WHEN** 用户打开 Appearance
- **THEN** 顶部展示 Follow System、Light、Dark 三个主题选项及当前选择，随后显示 Input Background 菜单（Cat、Shark、Off，默认 Cat），最后显示 Finish Animation 菜单（Drift Away、Fly Away）

#### Scenario: Browse General after the move
- **WHEN** 用户打开 General
- **THEN** 页面不显示 Finish Animation，不留下重复入口或空分组

#### Scenario: 精简外观说明
- **WHEN** 用户查看主题卡或动画菜单
- **THEN** 常驻内容只有必要标签、选中状态与控件；仍可通过悬停或辅助技术获取主题含义、成功后播放及遵循 Reduce Motion 的说明

### Requirement: 输入框背景独立保存并立即生效

Input Background SHALL 使用独立的本机 `editorBackgroundStyle` 偏好保存 Cat、Shark、Off，未保存或无法识别时默认 Cat。切换 SHALL 立即选择一套装饰或关闭，保留主题、提交动画和其他偏好；应用重启后恢复有效选择。背景行为与正文保护 SHALL 遵循 `launcher-appearance`。该菜单 SHALL 可通过键盘及辅助技术读取和选择。

#### Scenario: 切换并恢复背景
- **WHEN** 用户选择 Cat、Shark 或 Off 后重新打开设置或重启应用
- **THEN** 恢复所选背景；Shark 只有单条鲨鱼，没有海底；关闭不保留背景动画或鼠标监听；既有草稿及编辑器不因选择发生重建

### Requirement: General groups controls by user decision

General SHALL 依次展示 Quick Entry、Notifications、Startup、Troubleshooting；Quick Entry 内依次展示既有快捷键及相关反馈、Selected Text 权限状态与主动授权／系统设置入口、Use Pointer's Screen 和既有 Chrome 来源控件。Selected Text 的读取与授权规则 SHALL 遵循 `selected-text-capture`，不新增摘录快捷键或重复设置入口。Notifications 包含 Completion Notifications；Startup 内依次展示 Open at Login、Show Dock Icon；Troubleshooting 内先展示默认折叠的 App Logs，再展示 Local Records。侧栏 SHALL 不再包含 App Suggestions 页面。

#### Scenario: Browse routine controls
- **WHEN** 用户打开 General
- **THEN** 控件按规定分组和顺序呈现，各控件只有一个入口；App Suggestions 页面不再出现，Local Records 可在 Troubleshooting 中管理

#### Scenario: A shortcut conflict needs attention
- **WHEN** 当前快捷键存在冲突或系统提供推荐快捷键
- **THEN** 问题说明、推荐快捷键和 Use This Shortcut 仍紧邻快捷键控件；采用推荐值继续按原规则更新状态

#### Scenario: A system preference cannot be applied
- **WHEN** 登录启动或 Dock 图标设置未能应用
- **THEN** 相应控件附近继续显示原有失败或未应用提示，页面重排不隐藏反馈或将失败呈现为成功

#### Scenario: Find selected text authorization
- **WHEN** 用户在最小设置窗口中使用键盘或辅助技术浏览 Quick Entry
- **THEN** 可到达并获知 Selected Text 状态、读取范围与授权操作；打开设置本身不弹授权，不改变 Chrome 来源开关、现有快捷键或其他偏好

### Requirement: 日志与本地记录保留独立且精简的控件

Troubleshooting SHALL 分别说明 App Logs 保存不含草稿正文和密钥的技术诊断、Local Records 保存包含未提交文字的本机文本与活动。App Logs SHALL 保留默认折叠及现有打开文件夹、导出、清空操作，不新增日志开关、级别、筛选或保留天数选项。Local Records SHALL 沿用 `app-suggestions-settings` 中的记录开关、导出和默认折叠的 Manage Records，不增加包裹全部记录控件的折叠层。两类数据的存储、导出及删除 SHALL 保持独立；页面调整 MUST NOT 改变采集偏好、保留期限或已有数据。

#### Scenario: 浏览精简的排障区域
- **WHEN** 用户打开 General 并滚动到 Troubleshooting
- **THEN** App Logs 默认折叠，诊断范围说明可见；Local Records 的记录开关、包含未提交文字的说明和导出按钮可见，详细计数、保留天数及清空操作收在 Manage Records 中

#### Scenario: 独立清空两类数据
- **WHEN** 用户确认清空 App Logs 或 Local Records
- **THEN** 只清空所选类别的数据；另一类别、当前草稿及无关偏好保持不变，关闭记录仍沿用停止并删除的独立确认

#### Scenario: 从指南找到本地记录
- **WHEN** 用户在 Quick Guide 点击 Manage Local Records
- **THEN** 打开 General 并滚动到 Local Records；指南的说明指向 General → Troubleshooting，不再提供 App Suggestions 入口，也不声称本地应用匹配会发送草稿到远程服务

### Requirement: Reorganization preserves saved behavior

系统 SHALL 继续使用既有主题和动画选择，无需用户重新设置；未保存动画选择时仍默认 Drift Away。动画选择 SHALL 与 Completion Notifications 独立；移动控件 SHALL 不改变动画触发条件、减少动态效果处理及执行失败恢复。其余偏好语义遵循 `docs/product/settings.md`。

#### Scenario: Previously saved choices remain selected
- **WHEN** 用户已有任一有效主题和动画选择，在更新后打开设置或重新启动应用
- **THEN** Appearance 显示原有选择；修改后再次打开仍显示新选择，不重置通知、快捷键、屏幕位置、登录启动或 Dock 图标偏好

#### Scenario: Animation selection does not enable notifications
- **WHEN** 用户在完成通知关闭时切换动画
- **THEN** 完成通知仍关闭，下一次满足既有动画条件的提交使用所选效果

#### Scenario: Reduce Motion remains effective
- **WHEN** 用户启用 macOS Reduce Motion 后触发提交动画
- **THEN** 应用沿用现有简化动画行为，而不因选择菜单移到 Appearance 播放完整动态效果

### Requirement: Reorganized pages remain accessible

这两页 SHALL 沿用现有可滚动分组表单和窗口尺寸，在最小 760 × 560 pt 窗口中让全部控件可达；主题与动画选择 SHALL 支持键盘操作并向辅助技术表达名称及当前状态。

#### Scenario: Navigate in a small window
- **WHEN** 用户在最小设置窗口中通过滚动与键盘浏览这两页
- **THEN** 可以到达每个控件及其必要说明，焦点可辨认，不因固定高度或裁切丢失动画菜单、错误提示或诊断入口

### Requirement: 设置说明按操作需要展示

常规设置页 SHALL 不显示仅重复标题或控件的副标题；Templates 可保留通过 `@` 使用模板的提示，独立 action 详情可保留其用途说明。控件帮助 SHALL 优先解释非显然的行为；数据发送范围、服务计费、授权操作、本机记录范围及删除后果 SHALL 继续在相关控件或确认处可见，错误不得收进默认折叠的说明。AI Services SHALL 暂时隐藏当前服务卡片、Jotway AI 激活／额度区域及 Personal Model 标题，直接展示个人配置表单，并保留连接测试实际使用的服务与计费说明；配置与路由规则遵循 `model-capabilities`。

#### Scenario: 查看精简的 Notes 与写作设置
- **WHEN** 用户打开 Apple Notes 或 Writing Preferences
- **THEN** Notes 保留目的地、归集及回顾控件和数据共享说明，不显示静态标题说明及停用 Tags 分组；写作设置保留自动请求的数据发送说明、提示词作用范围和显式保存按钮，Enter 换行提示通过悬停及辅助技术可读，不占常驻底栏；已有标签和背景值不被删除或迁移

#### Scenario: 按需阅读使用指南
- **WHEN** 用户打开 Quick Guide
- **THEN** 首屏用三个步骤说明打开输入、检查目标和确认，保留快捷键及示例；详细快捷键、应用与 AI 行为、草稿恢复及隐私说明可以展开阅读，标题生成、Instant Insight 和打开回顾的方法仍可找到；移除重复的概述与已不适用的等待写作帮助说明

#### Scenario: 隐私与删除信息仍在操作处可见
- **WHEN** 用户查看 Chrome 来源、AI、Notes 归集／回顾、本地记录，或确认清空／停止记录
- **THEN** 仍可看到相关发送范围、计费、权限或删除后果；简化文案不改变开关、授权、记录、模型请求或删除的执行行为
