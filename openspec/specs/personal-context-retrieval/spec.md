# personal-context-retrieval Specification

## Purpose

在用户提问后，从其允许的 Notes、Reminders 和 Calendar 范围整理有界、可追溯的个人资料供回答使用。明确区分未完成事项、时间安排、历史线索及读取限制，使连续问答不会把缺少资料或陈旧计划当成当前事实。

## Requirements

### Requirement: Notes indexing starts automatically after authorization

共享 Notes 索引管理器 SHALL 在读取权限有效、embedding 密钥已保存、功能启用、范围非空且未暂停时自动开始首次索引，无需手动点击索引按钮。无启用偏好时默认开启；明确关闭、自定义范围及清空后的暂停 SHALL 保留。被动检查 SHALL NOT 请求系统权限。

#### Scenario: Authorization and key become ready in either order
- **WHEN** 用户完成 Notes 授权且 embedding 密钥已配置，或已授权后保存密钥，或带着有效权限和配置重启应用/返回应用
- **THEN** 唯一索引实例自动开始或恢复准备，在设置中显示进度；授权未授予时不枚举正文、不请求 embedding，也不后台弹授权框

#### Scenario: Pause or clear survives automatic triggers
- **WHEN** 用户关闭功能、取消同步或清空索引后重开设置、返回应用或重启
- **THEN** 不自动继续读取或重建；取消保留已完成批次，清空保留原始 Notes，显式重新启用或恢复后才能继续；配置变化时取消的旧同步结束后最多启动一次使用最新配置的同步

### Requirement: Retired question reading preserves shared Notes services

系统 SHALL 移除 Personal Agent 专用的来源设置、问题日期规划、资料读取、分批摘要和回答证据处理。旧个人来源偏好不再控制 Notes 存入或检索。Notes 共享索引、Related History、embedding 配置、范围、自动准备和暂停语义 SHALL 保持原契约，暂停问答不得清空、停用或重建这些共享数据，也不得增加另一个个人资料入口。

#### Scenario: Notes history continues without an agent
- **WHEN** Personal Agent 不再注册，Notes 检索原已配置可用
- **THEN** Notes 设置中的索引状态、文件夹范围、Search History 和补充检索继续工作，向量空间身份和已发布记录不变

#### Scenario: Old personal source restrictions remain inactive
- **WHEN** 旧偏好保存了 Personal Agent 的 Notes 关闭或自定义来源范围
- **THEN** 不加载该问答配置来限制或扩大 Notes 的共享范围；Notes 原有关闭、范围和暂停偏好保持有效

#### Scenario: Shared indexing remains paused
- **WHEN** 用户此前取消索引、清空后暂停或显式关闭 Related History
- **THEN** 移除 Personal Agent 和新增模型主备链均不恢复索引，不发送问答或额外 embedding 请求
