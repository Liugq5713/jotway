# personal-agent-conversation Specification

## Purpose

让用户通过显式选择 Personal Agent，在快速记录面板内提问、阅读回答并连续追问。会话只属于本次交互，固定回答区保持窗口稳定，关闭后结束上下文并隔离迟到结果，同时保留其他 action 的既有行为。

## Requirements

### Requirement: Personal Agent remains retired

系统 SHALL 暂时移除 Personal Agent 的 action 注册、目标选择、@ 入口、Apps 设置、setup、回答区、追问／重试和问答运行路径。旧启用、可见性、排序及来源偏好 SHALL 保留为不生效数据，不可恢复入口；旧 `@personal` 成为普通正文。历史调试文件不主动读取或删除，不创建新会话归档；不增加自动恢复或替代问答功能。Notes、Codex、Clipboard 及普通草稿的执行和失败恢复继续遵循各自契约。

#### Scenario: Upgrade with Personal Agent enabled
- **WHEN** 用户升级前启用了 Personal Agent 并保存其菜单顺序或来源范围
- **THEN** 设置、目标菜单和 @ 候选均无 Personal Agent，保存值不能注册或执行它，其他 action 的配置不变

#### Scenario: Old mention is ordinary text
- **WHEN** 用户输入 `@personal 帮我整理最近的想法`
- **THEN** 不启动会话、不移除该前缀、不显示回答区或问答 setup；按当前普通草稿路由处理，只有用户确认后才执行所选目标

#### Scenario: Ordinary question does not start an assistant
- **WHEN** 用户输入疑问句、打开面板或切换默认目标
- **THEN** 不进行 Personal Agent 规划、资料读取、摘要或回答，不发出对应模型请求；Notes 的存入和可选补充仍需沿用各自确认边界

#### Scenario: Retain data while retiring code
- **WHEN** 用户保留旧来源偏好、模型密钥、Notes 索引和历史 Personal Agent 调试目录
- **THEN** 不清理这些数据、不为暂停重建索引，不创建新会话文件，也不根据旧配置自动恢复功能
