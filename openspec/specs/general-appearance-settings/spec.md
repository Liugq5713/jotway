# general-appearance-settings Specification

## Purpose

定义 General 与 Appearance 的设置归属和浏览顺序，让用户能按启动、输入、通知和视觉偏好找到控制项；整理页面时保留已保存选择、必要错误提示与键盘可达性。

## Requirements

### Requirement: Appearance owns theme and finish animation

Appearance SHALL 按 Color Theme、Finish Animation 的顺序展示主题与动画设置；General SHALL 不再包含动画选择。页面说明 SHALL 同时涵盖颜色与动画，并保留减少动态效果的说明。

#### Scenario: Find visual preferences
- **WHEN** 用户打开 Appearance
- **THEN** 顶部展示 Follow System、Light、Dark 三个主题选项及当前选择，随后显示 Finish Animation 菜单，选项仍为 Drift Away 和 Fly Away

#### Scenario: Browse General after the move
- **WHEN** 用户打开 General
- **THEN** 页面不显示 Finish Animation，不留下重复入口或空分组

### Requirement: General groups controls by user decision

General SHALL 依次展示 Quick Entry、Notifications、Startup、Diagnostics；Quick Entry 内依次展示既有快捷键及相关反馈、Selected Text 权限状态与主动授权／系统设置入口、Use Pointer's Screen 和既有 Chrome 来源控件。Selected Text 的读取与授权规则 SHALL 遵循 `selected-text-capture`，不新增摘录快捷键或重复设置入口。Notifications 包含 Completion Notifications；Startup 内依次展示 Open at Login、Show Dock Icon；Diagnostics 保留默认折叠的 Runtime Logs。

#### Scenario: Browse routine controls
- **WHEN** 用户打开 General
- **THEN** 控件按规定分组和顺序呈现，各控件只有一个入口，侧栏页面及其他页面内容不受本次调整影响

#### Scenario: A shortcut conflict needs attention
- **WHEN** 当前快捷键存在冲突或系统提供推荐快捷键
- **THEN** 问题说明、推荐快捷键和 Use This Shortcut 仍紧邻快捷键控件；采用推荐值继续按原规则更新状态

#### Scenario: A system preference cannot be applied
- **WHEN** 登录启动或 Dock 图标设置未能应用
- **THEN** 相应控件附近继续显示原有失败或未应用提示，页面重排不隐藏反馈或将失败呈现为成功

#### Scenario: Find selected text authorization
- **WHEN** 用户在最小设置窗口中使用键盘或辅助技术浏览 Quick Entry
- **THEN** 可到达并获知 Selected Text 状态、读取范围与授权操作；打开设置本身不弹授权，不改变 Chrome 来源开关、现有快捷键或其他偏好

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
