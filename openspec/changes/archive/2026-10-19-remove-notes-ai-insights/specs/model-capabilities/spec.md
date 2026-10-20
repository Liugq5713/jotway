# Spec Delta

## MODIFIED Requirements

### Requirement: One personal text model

AI Services SHALL 只提供一套个人文本配置：服务类型、HTTPS API Base URL、API Key、Model ID，以及保存、移除 key 和测试连接。服务类型 SHALL 支持 Claude 原生 Messages 和 OpenAI Chat Completions 兼容接口。SHALL NOT 提供主备、交换、按 fast/deep 分别选择模型的设置。Notes 归集配置入口 SHALL 跳转到同一 AI Services 页面，不再打开重复的配置表单。fast/deep 仅决定业务用途、期限和流式行为，在个人模式下共享同一模型与凭据。

#### Scenario: All text features share one personal model
- **WHEN** 没有 Jotway code，个人模型配置与 key 可用
- **THEN** 标题、思考提示、归集及今天和周回顾使用同一个人模型，失败不调用其他模型

#### Scenario: Change personal service
- **WHEN** 用户修改服务类型或 API 地址并保存
- **THEN** 要求重新输入 key，不把旧 key 自动发给新地址；修改模型名称但保持相同服务与地址可保留已存 key

### Requirement: Complete streaming results

deep 请求及其连接测试 SHALL 使用流式传输。OpenAI SSE SHALL 收到有效 stop 与 `[DONE]`；Claude SSE SHALL 验证 message_start、内容块开始／结束、end_turn 和 message_stop。Claude 思考块可以跳过但不得进入回答，未知未来元数据事件可忽略，错误事件及缺少结束标记不能作为成功。所有响应有总字节上限，片段不超过业务上限，取消检查贯穿读取与发布。fast 默认使用普通 JSON 响应。失败不自动改发非流式请求。

#### Scenario: Preview and persistence
- **WHEN** 已验证身份的当前请求产生文本片段
- **THEN** 仅作为带调用身份和有效期限的临时预览；只有完整结束且业务校验成功才可进入回顾缓存；保存 Notes 不生成或写入补充
