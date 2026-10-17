# app-suggestions-settings Specification

## Purpose

让用户在 App Suggestions 中快速管理建议服务与本地操作记录，通过精简的默认界面和可展开的低频设置降低阅读负担，同时清楚呈现数据保存范围、异常状态和删除后果。

## Requirements

### Requirement: Retired custom phrase settings

系统 SHALL 移除 Your Phrases 设置和自定义前缀规则的运行时作用；已有规则偏好 MUST 保留原值但不再加载到路由或新记录的有效配置中。仅存在旧规则偏好 MUST NOT 被视为已配置的有效 action 设置。Jev 移除 SHALL 不恢复自定义短语规则。

#### Scenario: Existing phrase no longer determines a target
- **WHEN** 升级前保存了一个自定义前缀规则，用户重新启动后输入匹配该前缀的草稿
- **THEN** 系统使用剩余的正常路由决定目标，不因旧规则选中 action，且旧规则偏好原值不被重写或删除

#### Scenario: Phrase controls are absent
- **WHEN** 用户打开 App Suggestions 或 Quick Guide
- **THEN** 不再出现 Your Phrases 或 Jev 配置入口及使用说明；Local Records 的设置和管理仍可使用

### Requirement: Compact local record controls

Local Records SHALL 默认呈现记录开关、说明保存包含未提交文字的本机文本与活动、导出按钮，以及折叠的 Manage Records。保存天数、空间、详细计数与清空操作 SHALL 位于该折叠区内；展开状态 MUST NOT 改变记录设置。

#### Scenario: Open settings with saved preferences
- **WHEN** 用户重新进入 App Suggestions，已有自定义保存天数和记录开关状态
- **THEN** Manage Records 默认折叠，开关反映现有状态，说明明确提及未提交文字；不重置保存天数或记录内容

#### Scenario: Manage record details
- **WHEN** 用户展开 Manage Records
- **THEN** 可查看空间、文本版本/尝试/事件计数、待保存数量及保存期限说明，可修改保存天数或发起清空；收起不改变已保存的设置

### Requirement: Visible record exceptions and action feedback

系统 SHALL 在完整性正常时省略常驻正常提示，将缺失记录、完整性未知、统计不可用和操作失败直接显示在折叠区外。导出或管理操作的进行中、成功与失败反馈 SHALL 保持可见；操作进行中 MUST 阻止重复执行冲突操作。

#### Scenario: Healthy idle recorder
- **WHEN** 记录完整性正常、统计可用且没有进行中或刚完成的用户操作
- **THEN** 默认卡片不显示正常完整性声明或详细计数

#### Scenario: Recorder becomes incomplete or unavailable
- **WHEN** Manage Records 折叠时出现记录缺失、完整性未知或无法读取统计的状态
- **THEN** 卡片直接显示对应的简短提示；再次确认正常后不继续展示过期警告

#### Scenario: Export succeeds or fails
- **WHEN** 用户点击 Export Records 并完成目标文件夹选择
- **THEN** 保留现有 JSONL/CSV 导出内容和格式，操作期间显示进度并阻止重复操作，成功后可定位导出文件，失败提示无需展开管理区即可看到

#### Scenario: Export folder selection is cancelled
- **WHEN** 用户取消导出文件夹选择
- **THEN** 不导出或删除记录，解除忙碌状态并恢复可用控件

### Requirement: Confirmed destructive record controls

关闭记录和清空记录 SHALL 分别保留明确的确认弹窗：关闭会停止采集并删除已有记录，清空只删除已有记录。取消 MUST 保持开关和记录不变；相关操作 MUST NOT 修改当前草稿、应用使用记录、旧短语偏好或 App Logs。

#### Scenario: Cancel stop and delete
- **WHEN** 用户关闭记录开关后，在说明“停止并删除已有记录”的弹窗中取消
- **THEN** 记录保持开启，已有记录不变

#### Scenario: Confirm stop and delete
- **WHEN** 用户确认停止并删除，操作成功
- **THEN** 记录开关关闭、已有记录删除，迟到回调不恢复已删除记录

#### Scenario: Clear without disabling
- **WHEN** 用户展开 Manage Records 并发起清空
- **THEN** 确认前不删除数据；取消保留记录，确认成功后删除已有记录且维持原采集开关状态

### Requirement: Historical record compatibility

系统 SHALL 继续读取和导出含用户规则、Jev 来源及旧配置快照的历史操作记录，保留其原始含义。新采集的配置 MUST 不包含已退出的有效自定义规则、Jev 模型问题、阈值或有效绑定；本地应用匹配 SHALL 记录为本地来源，不伪造模型请求。历史内容 MUST NOT 重新参与路由，移除 Jev SHALL 不清空记录或改变既有采集及保留偏好。

#### Scenario: Export historical rule selection
- **WHEN** 已有操作记录表示某次目标由用户规则选中，用户在新版本导出记录
- **THEN** 该条记录及原配置快照可正常导出，来源含义不被改为模型或默认选择

#### Scenario: Capture after upgrade
- **WHEN** 新版本在保留旧规则及 Jev 偏好的情况下采集一次新输入和目标选择
- **THEN** 新记录不声明使用了自定义规则或 Jev；本地应用建议、手动选择和默认路由按实际来源记录，旧记录保持不变

#### Scenario: Export a historical Jev decision
- **WHEN** 用户导出升级前含 Jev 模型、选项分数、规则版本或请求结果的操作记录
- **THEN** 旧信息仍可读取并按原意导出，不要求加载 Jev 服务、恢复凭据或发起网络请求

### Requirement: Jev service settings are retired without removing local records

系统 SHALL 移除 Jev 密钥输入、保存/替换/删除、连接测试、状态和计费说明；启动、打开设置或输入草稿 SHALL 不读取旧 Jev 凭据或请求 Jev，也不主动删除旧凭据。App Suggestions SHALL 保留 Local Records；记录开关、保存期限、导出、异常提示、管理区与删除确认沿用现有契约。

#### Scenario: Open settings after an upgrade
- **WHEN** 用户保留旧 Jev 密钥、已启用记录及自定义保存天数，升级并打开 App Suggestions
- **THEN** 不出现 Jev 服务卡片或连接测试，不访问 Jev 凭据或网络；Local Records 保留原开关和天数，管理区默认折叠，旧凭据和已有记录不被删除

#### Scenario: Manage records without a suggestion service
- **WHEN** 用户在没有 Jev 服务的版本导出、调整保存期限或发起清空记录
- **THEN** 操作无需模型配置；现有反馈、冲突操作保护及删除确认保持，取消确认不删除记录
