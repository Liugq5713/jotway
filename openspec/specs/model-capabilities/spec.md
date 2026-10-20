# model-capabilities Specification

## Purpose

统一文本模型配置与调用。业务保留 fast、deep 能力划分，用户只配置一个个人文本模型；Jotway AI 激活码始终优先。

## Requirements

### Requirement: One personal text model

AI Services SHALL 只提供一套个人文本配置：服务类型、HTTPS API Base URL、API Key、Model ID，以及保存、移除 key 和测试连接。服务类型 SHALL 支持 Claude 原生 Messages 和 OpenAI Chat Completions 兼容接口。SHALL NOT 提供主备、交换、按 fast/deep 分别选择模型的设置。Notes 归集配置入口 SHALL 跳转到同一 AI Services 页面，不再打开重复的配置表单。fast/deep 仅决定业务用途、期限和流式行为，在个人模式下共享同一模型与凭据。

#### Scenario: All text features share one personal model
- **WHEN** 没有 Jotway code，个人模型配置与 key 可用
- **THEN** 标题、思考提示、归集及今天和周回顾使用同一个人模型，失败不调用其他模型

#### Scenario: Change personal service
- **WHEN** 用户修改服务类型或 API 地址并保存
- **THEN** 要求重新输入 key，不把旧 key 自动发给新地址；修改模型名称但保持相同服务与地址可保留已存 key

### Requirement: AI Services 暂时精简展示

AI Services SHALL 暂时隐藏当前文本服务卡片和 Jotway AI 激活／额度区域；个人模型表单 SHALL 直接展示，不显示 Personal Model 标题或折叠入口。隐藏项的界面代码与功能实现 SHALL 保留，可通过展示开关恢复。服务类型、API 地址、模型、密钥和原有保存、移除密钥、连接测试操作 SHALL 继续可用。此界面调整 SHALL 保留已有配置、凭据和托管优先规则；连接测试 SHALL 继续说明实际调用服务和计费范围。

#### Scenario: 直接配置个人模型
- **WHEN** 用户打开 AI Services
- **THEN** 不显示当前服务、Jotway AI 激活／额度卡片或 Personal Model 标题，服务商、密钥、模型及保存／测试操作直接可见；地址与协议可在高级设置中展开

#### Scenario: 已有托管配置继续生效
- **WHEN** 用户已有激活码并打开 AI Services
- **THEN** 个人表单直接可见，已有配置与凭据保持原值，连接测试说明使用 Jotway AI 额度，实际请求仍遵循托管优先规则

### Requirement: Hosted code has routing priority

统一配置入口 SHALL 在解析个人模型前检查激活码。已存 code（包括暂时无法读取的凭据）SHALL 阻止个人直连，快速文字用托管 Flash，深度文字用托管 Pro。无效、停用、额度不足、网络故障或本地凭据读取失败 SHALL 返回对应错误，不回退个人 key。激活、换码和刷新账户 SHALL 不改写个人配置。移除 code 后，后续新请求 SHALL 恢复已保存的个人模型；没有个人模型则提示配置，原文仍可存入。此规则涵盖文本模型连接测试；不再提供 embedding 能力。

#### Scenario: Both credentials are present
- **WHEN** 已有个人 key，再激活 Jotway code
- **THEN** 后续文本生成和测试只走 Jotway；个人配置保留；code 失败也不向个人服务发送请求

#### Scenario: Remove code
- **WHEN** 用户移除 code
- **THEN** 后续请求使用原个人配置，已有冻结调用不改投服务；当前设置页暂不提供移除入口

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
- **THEN** 仅作为带调用身份和有效期限的临时预览；只有完整结束且业务校验成功才可进入回顾缓存；保存 Notes 不生成或写入补充

### Requirement: Settings tests and privacy

连接测试 SHALL 使用固定样例、当前生效服务及同一调用入口，不发送草稿。未保存编辑、配置或 key 变化、页面退出 SHALL 取消或清除旧测试结论。有 code 时 SHALL 明确标示测试使用 Jotway 额度；无 code 时披露内容发往个人配置服务并由该账户计费。保存或打开个人模型表单 SHALL 不触发模型请求。错误不展示 key 或原始服务端响应，常规日志只保留调用身份、模型、阶段、耗时及固定错误类别。

#### Scenario: 使用当前配置执行连接测试
- **WHEN** 用户执行连接测试，随后修改配置或 key、保留未保存编辑或退出页面
- **THEN** 测试仅向当前生效服务发送固定样例而不发送草稿；变更或退出取消或清除旧结论，说明 Jotway 额度或个人服务计费边界，不展示 key 或原始服务端响应；仅保存或打开个人表单不发起请求

#### Scenario: 区分目录加载与实际生成
- **WHEN** 用户查看模型列表或执行生成测试
- **THEN** 目录成功仅表示收到模型列表；生成测试按钮与结果明确标示实际服务及模型，有激活码时标为测试 Jotway AI，并说明个人配置尚未生效

### Requirement: Text-only model configuration

系统 SHALL 仅提供 fast 和 deep 文本能力，不提供 embedding 模型、地址、key、连接测试或历史检索入口。旧 embedding 配置 SHALL NOT 触发请求或后台索引。Notes 今天／周回顾 SHALL 独立读取已授权范围内的原文并使用当前文本模型。

#### Scenario: 旧向量配置保持停用
- **WHEN** 用户打开模型设置或应用带有旧 embedding 配置
- **THEN** 仅提供 fast 和 deep 文本能力，不出现 embedding 配置、连接测试或历史检索入口，也不据旧配置发起请求或后台索引；Notes 今天／周回顾独立读取已授权范围原文并使用当前文本模型

### Requirement: 写作背景说明作为输入框占位提示

Writing Preferences 中的 About Your Writing SHALL 默认折叠，折叠区外始终说明文字保存在本机，但当前写作功能不使用它。展开后的空输入框 SHALL 提供仅供参考的简短占位提示；非空时隐藏，清空后恢复。提示不属于编辑值，不得保存或发送为用户背景。输入框 SHALL 保留独立名称、悬停与辅助说明；占位层不拦截点击，也不形成重复的辅助技术朗读项。保存、取消、恢复默认及 Enter 换行行为 SHALL 保持不变；折叠和展开不得丢失未保存编辑。Instant Insight 提示词编辑器 SHALL 保留精简的上方说明，明确同时用于手动和自动请求并随请求发给 AI。

#### Scenario: 空背景输入框显示提示
- **WHEN** 用户展开没有已保存背景的编辑器，或清空编辑文字
- **THEN** 简短参考提示显示在输入框内，点击提示区域可以编辑；聚焦本身不隐藏提示，也不填入或保存提示文字；当前功能不使用背景的说明仍可见

#### Scenario: 编辑已有背景
- **WHEN** 用户打开有已保存背景的编辑器，或开始输入文字
- **THEN** 只显示实际编辑文字，占位提示隐藏；用户仍能通过悬停帮助或辅助技术获取解释，Enter 仍插入换行

#### Scenario: 恢复默认与取消
- **WHEN** 用户恢复空白默认值，随后取消或保存
- **THEN** 恢复默认时占位提示重新出现；取消恢复已保存背景并按内容显示或隐藏提示，保存只提交实际背景值

#### Scenario: 折叠不丢失编辑
- **WHEN** 用户编辑背景文字后折叠并重新展开 About Your Writing
- **THEN** 未保存文字仍保留，只有保存才更新本机配置；编辑和展开不发起模型请求，保存反馈不声称影响后续写作请求

### Requirement: 写作背景准确说明当前作用范围

当前 Instant Insight、Notes 首次标题、归集、回顾及设置页 Check Connection SHALL 不自动加入该背景；仅精简界面不得将背景接入这些功能。已有 `plugin.ai.manualConfiguration` 值 SHALL 原样保留，不进行清理或迁移。保留代码中的旧连接测试回调可读取该背景，但没有当前界面调用入口；界面 SHALL 不宣称所有写作工具共用该背景。

#### Scenario: 已有背景不影响当前写作请求
- **WHEN** 用户保存背景后请求 Instant Insight、Notes 标题、归集、回顾或设置页连接测试
- **THEN** 请求继续使用各自原有输入与提示词，不合入该背景；背景值仍可在写作偏好中展开查看和编辑

### Requirement: 个人服务商预设

AI Services SHALL 提供 DeepSeek、Kimi、OpenAI、Claude 和自定义入口。预设 SHALL 提供相应协议、官方 API 地址和 Key 获取链接。地址与协议 SHALL 放入高级设置，自定义入口展开高级设置。修改为不匹配预设的地址或协议 SHALL 显示自定义服务。已有个人配置 SHALL 原样载入，模型仍可手填，不引入多账号或额外持久化凭据。

#### Scenario: 选择常用服务
- **WHEN** 用户切换为另一服务商预设
- **THEN** 预填地址和协议，清空未保存的 key 与模型选择；用户显式保存后才改变生效配置，不自动请求网络

#### Scenario: 载入已有配置
- **WHEN** 用户打开保存有个人模型的设置
- **THEN** 保留原地址、协议和模型；识别匹配的预设，否则显示自定义；不会覆盖存储值或自动选择新模型

#### Scenario: 清晰浏览个人配置表单
- **WHEN** 用户填写个人服务配置
- **THEN** 字段标签位于全宽控件上方，密钥获取与模型加载分别紧邻对应标签；凭据、模型及保存／测试分区展示，手填与列表切换为轻量入口；保存为主操作，测试为次操作，移除密钥与主操作分开

#### Scenario: 阅读状态与必要说明
- **WHEN** 存在未保存编辑、加载失败、测试结果或较长的配置内容
- **THEN** 明确提示保存后才能测试，错误与测试结果以图标和文字呈现；请求目标、发送范围和计费说明继续可见，表单可滚动访问全部控件，不裁切错误或测试结果

### Requirement: 显式加载个人模型目录

模型目录 SHALL 仅由用户显式操作加载，使用当前个人表单的 HTTPS 地址和 key，不发送草稿。无新 key 时仅可复用相同规范化地址与协议的已存个人 key。请求 SHALL 拒绝重定向、限制时间与响应大小，错误不得包含 key 或原始服务响应。列表仅在当前页面内存保留；模型选择与生成验证独立。

#### Scenario: 加载并选择模型
- **WHEN** 用户显式加载列表并收到有效模型
- **THEN** 展示可选择的模型，保留原选择且不自动选中第一项；用户也可手填列表外的模型 ID，保存仍需要非空合法模型

#### Scenario: 目录失败或不完整
- **WHEN** 服务不支持目录、返回错误、空列表或超出单次展示范围
- **THEN** 明确说明状态与手填方式，不清空原模型，不将目录成功当作文本能力验证；分页服务只展示首批并说明列表可能不完整

#### Scenario: 编辑及退出使目录失效
- **WHEN** 请求期间修改服务、地址、key 或模型，已存个人配置／凭据变化，或离开页面
- **THEN** 取消旧请求并丢弃迟到结果；地址、协议或 key 改变时清除旧目录，已选模型不因目录请求失败而丢失
