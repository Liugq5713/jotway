# model-capabilities Specification

## Purpose

统一文本模型配置与调用。业务保留 fast、deep 能力划分，用户只配置一个个人文本模型；Jotway AI 激活码始终优先。

## Requirements

### Requirement: One personal text model

AI Services SHALL 只提供一套个人文本配置：服务类型、HTTPS API Base URL、API Key、Model ID，以及保存、移除 key 和测试连接。服务类型 SHALL 支持 Claude 原生 Messages 和 OpenAI Chat Completions 兼容接口。SHALL NOT 提供主备、交换、按 fast/deep 分别选择模型的设置。Notes 归集配置入口 SHALL 跳转到同一 AI Services 页面，不再打开重复的配置表单。fast/deep 仅决定业务用途、期限和流式行为，在个人模式下共享同一模型与凭据。

#### Scenario: All text features share one personal model
- **WHEN** 没有 Jotway code，个人模型配置与 key 可用
- **THEN** 标题、思考提示、归集、AI 补充及周月回顾使用同一个人模型，失败不调用其他模型

#### Scenario: Change personal service
- **WHEN** 用户修改服务类型或 API 地址并保存
- **THEN** 要求重新输入 key，不把旧 key 自动发给新地址；修改模型名称但保持相同服务与地址可保留已存 key

### Requirement: Hosted code has routing priority

统一配置入口 SHALL 在解析个人模型前检查激活码。已存 code（包括暂时无法读取的凭据）SHALL 阻止个人直连，快速文字用托管 Flash，深度文字用托管 Pro。无效、停用、额度不足、网络故障或本地凭据读取失败 SHALL 返回对应错误，不回退个人 key。激活、换码和刷新账户 SHALL 不改写个人配置。移除 code 后，后续新请求 SHALL 恢复已保存的个人模型；没有个人模型则提示配置，原文仍可存入。此规则涵盖文本模型连接测试；不再提供 embedding 能力。

#### Scenario: Both credentials are present
- **WHEN** 已有个人 key，再激活 Jotway code
- **THEN** 后续文本生成和测试只走 Jotway；个人配置保留；code 失败也不向个人服务发送请求

#### Scenario: Remove code
- **WHEN** 用户移除 code
- **THEN** 后续请求使用原个人配置，已有冻结调用不改投服务；设置在移除按钮附近说明恢复个人账户调用

### Requirement: Personal configuration migration

系统 SHALL 将旧 deep 主模型迁移为一个人配置，保留对应 DeepSeek 或 Moonshot 凭据，旧备用和独立 fast 选择不再执行。旧激活曾覆盖绑定时 SHALL 优先恢复明确保存的个人来源，否则选择已有 DeepSeek key、其次 Moonshot key；没有可恢复项则保持未配置。未知来源、未知型号和损坏值 SHALL 保留，不静默换成其他服务；用户可显式保存新配置修复。迁移 SHALL 不发起网络请求、不删除旧偏好或其他凭据。新个人配置使用版本化独立偏好；API Key 不进入普通偏好或日志。

#### Scenario: Existing personal key
- **WHEN** 旧 deep 为 Kimi 或 DeepSeek
- **THEN** 迁移后 fast/deep 共同使用该选择，已有 key 无需重新输入；保存新个人配置后使用独立个人 key 存储

### Requirement: Protocol adapters preserve business constraints

OpenAI 兼容接口 SHALL 使用 Base URL 下的 `chat/completions` 与 Bearer key；Claude SHALL 使用 Base URL 下的 `messages`、`x-api-key` 和明确 API 版本，system 指令在顶层。自定义 Base URL 仅允许 HTTPS，不含用户名、密码、查询或片段，不跟随重定向。常规兼容模型请求使用业务输出预算；Claude 与已知 Kimi Code 型号优先使用调用方声明的思考／输出总预算，思考内容不作为业务输出。通用接口和 Claude 的 JSON 任务 SHALL 明确要求纯 JSON，由原有业务解析验证；不得假定所有兼容服务都支持 JSON mode。已知 DeepSeek/Kimi 的专有字段只对其官方主机使用。

#### Scenario: User supplies a model alias
- **WHEN** 个人服务将模型别名解析为具体型号
- **THEN** 允许非空合法的返回模型 ID，并在同次流中保持身份一致；托管请求仍要求实际模型严格匹配固定型号

#### Scenario: Incomplete or unsupported result
- **WHEN** 返回工具调用、截断、空回答、错误或业务格式不符
- **THEN** 不冒充成功，不执行工具，不改投其他服务；Notes 继续沿用原文保护规则

### Requirement: Frozen configuration and bounded execution

每次逻辑调用 SHALL 冻结生效服务、模型、地址、凭据及配置版本；不在执行中读取新配置后改投。每个快照保持独立串行队列，fast 与 deep 不相互占用队列。文本调用只有一次服务尝试，fast 最多 120 秒、deep 最多 300 秒，包括排队；业务更短期限优先。到期或取消 SHALL 停止等待并丢弃迟到结果。个人标题既有同日恢复可在原服务重试，托管标题失败暂停自动重试；不恢复任何跨服务备用调用。改变个人配置在个人模式下使 fast/deep 均失效；托管模式下个人编辑不改变有效文本版本。换码及移除 code 使托管版本失效；账户余额刷新不改变配置版本。

#### Scenario: Change settings during a request
- **WHEN** 生成过程中保存新模型、激活或移除 code
- **THEN** 已冻结请求保持原服务并遵守业务失效检查，后续请求使用新配置；迟到内容不能覆盖已失效结果

### Requirement: Complete streaming results

deep 请求及其连接测试 SHALL 使用流式传输。OpenAI SSE SHALL 收到有效 stop 与 `[DONE]`；Claude SSE SHALL 验证 message_start、内容块开始／结束、end_turn 和 message_stop。Claude 思考块可以跳过但不得进入回答，未知未来元数据事件可忽略，错误事件及缺少结束标记不能作为成功。所有响应有总字节上限，片段不超过业务上限，取消检查贯穿读取与发布。fast 默认使用普通 JSON 响应。失败不自动改发非流式请求。

#### Scenario: Preview and persistence
- **WHEN** 已验证身份的当前请求产生文本片段
- **THEN** 仅作为带调用身份和有效期限的临时预览；只有完整结束且业务校验成功才可进入回顾缓存或 Notes 补充

### Requirement: Settings tests and privacy

连接测试 SHALL 使用固定样例、当前生效服务及同一调用入口，不发送草稿。未保存编辑、配置或 key 变化、页面退出 SHALL 取消或清除旧测试结论。有 code 时 SHALL 明确标示测试使用 Jotway 额度；无 code 时披露内容发往个人配置服务并由该账户计费。保存或打开个人模型表单 SHALL 不触发模型请求。错误不展示 key 或原始服务端响应，常规日志只保留调用身份、模型、阶段、耗时及固定错误类别。

### Requirement: Text-only model configuration

系统 SHALL 仅提供 fast 和 deep 文本能力，不提供 embedding 模型、地址、key、连接测试或历史检索入口。旧 embedding 配置 SHALL NOT 触发请求或后台索引。Notes 周/月回顾 SHALL 独立读取已授权范围内的原文并使用当前文本模型。
