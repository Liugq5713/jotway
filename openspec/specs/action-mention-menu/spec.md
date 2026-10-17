# action-mention-menu Specification

## Purpose

让用户在设置中控制快速记录面板的 @ 入口显示和顺序，减少低频项目干扰。统一菜单补全、手动名称解析和正文处理的生效范围，同时保留 action 的配置、执行能力以及既有自动意图识别资格。

## Requirements



### Requirement: Legacy action names remain literal draft content

系统 SHALL 停止解析全部 action 的 `@` 名称及别名，也不得经本地关键词或识别提示重新建立前缀指定能力。旧名称 SHALL 作为普通正文保留，不触发专属 setup、不删除前缀、不锁定目标；当前目标菜单选择优先，未选择时沿用普通本地匹配、既有识别资格和默认路由。历史操作记录中的旧路由来源与转换字段 SHALL 保持可读，新提交不得记录已取消的前缀指定或剥离转换。Personal Agent SHALL 不再注册，旧启用、排序或来源偏好不得恢复问答入口或会话。

#### Scenario: Old prefix cannot override an explicit target
- **WHEN** 用户通过目标菜单选择 Notes，输入 `@codex 帮我分析`
- **THEN** 仍按 Notes 处理，正文包含字面的 `@codex`；不启动 Codex 或其配置，也不因 Codex 不可用而阻止 Notes

#### Scenario: Registered unavailable aliases and removed names are ordinary text
- **WHEN** 用户输入 `@notes`、`@personal`、`@clipboard`、`@reminder` 或任何其他旧前缀，且没有相应显式目标
- **THEN** 名称是否注册、隐藏、被禁用或已移除均不赋予其指定能力；按普通草稿处理，Personal Agent 与 Clipboard 不因此被自动选择

#### Scenario: Choosing the same action still preserves the prefix
- **WHEN** 用户输入带旧前缀的草稿，再通过目标菜单选择对应 action
- **THEN** 旧前缀仍是可见的业务正文或查询文字，不因实际目标相同而被删除；沿用该 action 的普通空白处理

#### Scenario: Existing preferences and operation exports remain compatible
- **WHEN** 升级后保存偏好仍含 action @ 显示和顺序，或导出旧版本的操作记录
- **THEN** 偏好不影响模板或 action 入口，不被转换为自定义模板；历史记录仍可读取，新提交不产生前缀剥离事实
