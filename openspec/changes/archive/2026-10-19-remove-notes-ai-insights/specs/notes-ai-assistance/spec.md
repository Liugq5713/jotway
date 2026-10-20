# Spec Delta

## ADDED Requirements

### Requirement: Notes saves do not generate supplements

系统 SHALL NOT 在 Notes 保存过程中请求、生成、流式接收、采用或刷新洞察、额外想法、答案或相关内容。此规则适用于普通、归集及降级保存、启动和配置变化，不受旧补充偏好影响。保存 SHALL 保留完整原文，沿用标题与归集规则，不设置补充准备期限。

#### Scenario: Ordinary save with an old enabled preference
- **WHEN** 归集已关闭且旧补充偏好为开启
- **THEN** 完整原文与首次标题或待生成标题一同保存，不请求补充或等待五分钟补充期限

#### Scenario: Append a question to a topic
- **WHEN** 提交的草稿包含问题且追加到受管理主题
- **THEN** 问题作为原文保存，不生成答案、洞察、尾部或刷新任务

#### Scenario: Restart with unfinished supplementation
- **WHEN** 启动或配置变化遇到旧的未完成补充工作
- **THEN** 不恢复生成或刷新写入；已经发出但结果不明的写入仅通过读取核对

### Requirement: Supplement controls are removed

系统 SHALL 从设置移除 Notes Add Extra Ideas、偏好编辑器、专属帮助和旧改写提示。已有补充与改写值 SHALL 继续保存，但 SHALL NOT 作为活动功能配置或指令读取。通用 AI 配置及保留功能的写作偏好 SHALL 继续可用。

#### Scenario: Open settings after upgrade
- **WHEN** 用户打开 Notes 设置或写作偏好
- **THEN** 不显示补充开关、编辑器或链接；归集、回顾范围、自动思考提示和通用指令继续可用

#### Scenario: Saved instructions ask for additions
- **WHEN** 旧 Notes 补充偏好要求分析或相关链接
- **THEN** 不因此请求模型或追加 Notes 内容

### Requirement: Retained AI features stay independent

移除 Notes 补充 SHALL 保留语义标题与当天标题恢复、相关主题归集、只读今天／周回顾和草稿思考提示。标题恢复 SHALL 保持有保护的仅标题写入约束。回顾和思考提示 SHALL NOT 获得 Notes 写回路径。

#### Scenario: A pending title is recovered
- **WHEN** 已存笔记符合既有当天标题恢复规则
- **THEN** 可补全标题并保留每个非标题区域，不生成洞察

#### Scenario: User requests review or thinking help
- **WHEN** 用户请求保留的回顾或思考提示功能
- **THEN** 既有行为继续可用，其结果不写入 Notes

## REMOVED Requirements

### Requirement: Question-aware assistance

**Reason**: 移除 Notes AI 补充。
**Migration**: 停止生成与刷新；保留已存内容、边界和停用的旧偏好。标题、回顾与思考提示保持原约束。

### Requirement: Evidence and completion uncertainty

**Reason**: 移除 Notes AI 补充。
**Migration**: 停止生成与刷新；保留已存内容、边界和停用的旧偏好。标题、回顾与思考提示保持原约束。

### Requirement: Separate bounded additions

**Reason**: 移除 Notes AI 补充。
**Migration**: 停止生成与刷新；保留已存内容、边界和停用的旧偏好。标题、回顾与思考提示保持原约束。

### Requirement: Optional preparation reliability

**Reason**: 移除 Notes AI 补充。
**Migration**: 停止生成与刷新；保留已存内容、边界和停用的旧偏好。标题、回顾与思考提示保持原约束。

### Requirement: Preferences and action boundaries

**Reason**: 移除 Notes AI 补充。
**Migration**: 停止生成与刷新；保留已存内容、边界和停用的旧偏好。标题、回顾与思考提示保持原约束。

### Requirement: Content-free assistance diagnostics

**Reason**: 移除 Notes AI 补充。
**Migration**: 停止生成与刷新；保留已存内容、边界和停用的旧偏好。标题、回顾与思考提示保持原约束。

### Requirement: Streamed supplements are adopted only after completion

**Reason**: 移除 Notes AI 补充。
**Migration**: 停止生成与刷新；保留已存内容、边界和停用的旧偏好。标题、回顾与思考提示保持原约束。

### Requirement: 写作偏好统一入口

**Reason**: 移除 Notes AI 补充。
**Migration**: 停止生成与刷新；保留已存内容、边界和停用的旧偏好。标题、回顾与思考提示保持原约束。
