# model-capabilities Specification

## Purpose

为 Jotway 提供按 fast、deep、embedding 和 jev 分类的模型能力，使调用方通过稳定的输入输出约定使用现有服务。集中配置与明确的生命周期保证更换模型或未来接入统一 API 时，模型选择、凭据、结果校验和业务失败恢复仍然一致。

## Requirements

### Requirement: Three capability bindings

系统 SHALL 仅提供 `fast`、`deep`、`embedding` 三类能力；文字能力各保存一条有效的主备模型链，embedding 保持单一绑定。新配置默认 fast 为 DeepSeek Flash → `kimi-k2.7-code-highspeed`，deep 为 DeepSeek V4 Pro → `kimi-k2.7-code`，embedding 保持现有 Qwen 配置。业务调用方只选择能力。文字和向量 SHALL 保持各自输入输出约定，不增加按业务功能命名的配置。`jev` SHALL 不再作为可调用、可绑定或可配置能力，旧凭据不主动读取或删除。

#### Scenario: Fast and deep coexist
- **WHEN** 使用默认配置执行需要快速判断和深度文字生成的操作
- **THEN** 优先分别使用 Flash 和 Pro，符合切换条件时才调用各自的 Kimi 备用模型；业务输入不包含服务地址或凭据

#### Scenario: Bind a compatible replacement
- **WHEN** 某类保留能力绑定到另一个符合该类接口约定的适配器
- **THEN** 调用方继续使用原有输入输出与失败处理，不改写提示词或业务规则来适配网络协议

#### Scenario: Removed capability has no readiness state
- **WHEN** 用户保留旧 Jev 凭据，启动应用并打开 Writing Help
- **THEN** 仅展示三类能力的当前状态，不加载 Jev 凭据、构造 Jev 请求或展示 Jev 缺失/可用状态；已有明确模型选择及保留能力的凭据不被重置

### Requirement: Deep selection has one scope

系统 SHALL 在 Writing Help 为 fast 和 deep 分别提供主模型及可关闭的备用模型选择。fast 候选为 DeepSeek Flash 与 `kimi-k2.7-code-highspeed`，deep 候选为 DeepSeek V4 Pro 与 `kimi-k2.7-code`；同一链不得重复模型，顺序可交换。deep 配置影响 Notes 补充及每周／每月回顾，fast 配置影响 Notes 首次标题、归类及手动或用户开启自动追问后的草稿思考提示；Personal Agent 的规划、回答和分批摘要均不再调用。设置 SHALL 展示三类状态、每条链的顺序及分别可用性，embedding 独立，不恢复已移除 action 或 Jev 配置。

#### Scenario: Select Kimi for deep
- **WHEN** 用户配置 Kimi 密钥，将 deep 主模型设为 Kimi Code、备用设为 Pro
- **THEN** 后续 deep 操作优先使用 Kimi，只有符合切换条件时才尝试 Pro；fast 配置保持原值

#### Scenario: Label does not enable reasoning
- **WHEN** 用户保持 DeepSeek 主模型配置
- **THEN** Flash 和 Pro 保留 thinking disabled，不因能力名称自动开启思考；Kimi 型号自身的思考行为单独说明

#### Scenario: Reverse or disable fallback
- **WHEN** 用户交换 fast 主备顺序或将备用设为 None 后重启应用
- **THEN** 保存的完整顺序保持不变；None 下任何失败都不会调用第二个模型，deep 配置不变

#### Scenario: Duplicate or incompatible selection
- **WHEN** 用户尝试把同一模型放入主备两个位置，或把 deep 专用型号放入 fast
- **THEN** 设置不保存无效链；交换操作一次性提交两个不同位置，不产生中间重复配置

#### Scenario: Draft thinking reuses fast independently
- **WHEN** 用户在 Writing Help 更改 fast 主备链后，手动请求草稿思考提示，或已开启自动追问并满足停写规则
- **THEN** 本次提示使用新 fast 快照及其有界主备规则，不增加按功能命名的模型配置；deep、embedding 及 Notes 补充开关保持原值

#### Scenario: Reviews share the selected deep chain
- **WHEN** 用户请求每周或每月回顾
- **THEN** 本次请求冻结当前 deep 主备链，不增加回顾专用模型配置，也不受 Notes 补充开关控制

### Requirement: Saved choices and shared credentials survive migration

系统 SHALL 将已保存的来源／模型选择保留为 deep 主模型，新增配置不得覆盖未知选择、其他功能开关或手写偏好。Flash／Pro 共用 DeepSeek 凭据，两个 Kimi 型号共用 Moonshot 凭据；保存、替换和删除 SHALL 更新所有引用该凭据的主备链版本及状态。无法解析的主模型保持不可用，不以备用掩盖；备用缺少配置不阻断合法主模型。打开设置或迁移 SHALL NOT 发送模型请求或自动测试。

#### Scenario: Upgrade with existing Kimi selection
- **WHEN** 已保存 Kimi 来源选择的用户升级并打开设置
- **THEN** deep 主模型保留为 Kimi，使用本次支持的 Kimi Code 型号，原 Moonshot 密钥无需重新输入；其他功能偏好保持原值，不发生模型调用

#### Scenario: Shared key changes
- **WHEN** 从任一入口替换或删除 DeepSeek 或 Moonshot 密钥
- **THEN** 引用它作为主模型或备用模型的 fast／deep 版本和状态均更新；不改动另一家凭据，受影响连接测试结论失效

#### Scenario: Saved provider is unavailable
- **WHEN** 已保存主来源或模型未注册
- **THEN** 保留选择及凭据，显示不可用；修复前不自动选取或调用备用服务

#### Scenario: Missing fallback credentials
- **WHEN** 主模型已配置而备用密钥缺失、损坏或不可读取
- **THEN** 明确显示备用未就绪，主调用仍可执行；主调用失败后报告原因及备用不可用，不发送无凭据请求

### Requirement: Request options and result meaning remain caller owned

文字调用 SHALL 接收调用方组装的指令、内容、输出格式、预算、超时及可选流式回调。调用方 SHALL 显式区分非思考与思考模型的总 token 预算，不把 Flash 的 512-token 限额直接用于 Kimi；思考内容不作为回答或业务输出。能力模块执行通用协议和逐尝试模型校验；业务继续校验日期、候选、来源及输出含义。适配器无法满足必需约束时 SHALL 明确失败，不静默增大预算、截断输入或放宽校验。

#### Scenario: Reuse fast with different constraints
- **WHEN** Notes 归类指定 fast 的期限、JSON 输出和长度约束
- **THEN** 主备尝试遵守相同业务约束，归类继续验证候选身份；切换不改变资料或规则，不恢复问答规划

#### Scenario: Keep preferences separate from transport
- **WHEN** 一个调用需要业务专用提示词，而另一调用使用手写偏好
- **THEN** 各调用方只发送适用的已组装指令，执行模块不自行插入其他业务规则

#### Scenario: Thinking consumes its own declared budget
- **WHEN** fast 调用切换到 Kimi Highspeed
- **THEN** 使用调用方声明的思考模型总 token 预算，保留 JSON 输出及业务字节限制；不显示 reasoning_content，截断或不合法输出不能冒充成功

### Requirement: Frozen configuration and invalidation

系统 SHALL 在逻辑操作开始时冻结主备顺序、两路配置、预算及凭据，不在失败后重新读取当前设置。配置变化 SHALL 不把已发起操作改投新配置；存入及补充操作沿用其快照与现有有效性保护。备用只能来自已冻结的同一条链，不能因失败临时切换当前全局选择。取消、范围变化或版本失效后的结果 SHALL 不被采用。

#### Scenario: Switch deep during supplement preparation
- **WHEN** Notes 正在准备补充，用户修改 deep 主备顺序
- **THEN** 旧补充按现有业务检查失效或保留既有快照，不采用新顺序；不改变原文已存入的事实，下一次新操作使用新快照

#### Scenario: Switch deep during a multi-call answer
- **WHEN** 旧配置仍包含 Personal Agent 的多次调用偏好，用户在当前版本切换 deep
- **THEN** 不恢复摘要或回答任务，不展示旧会话结果；新顺序仅影响保留功能的后续新操作

#### Scenario: Switch deep after a save was accepted
- **WHEN** 已确认的存入操作冻结 Pro → Kimi 后，用户改成 Kimi → Pro
- **THEN** 本次操作不读取新顺序；其是否继续仍由既有业务有效性检查决定，后续新操作才使用新顺序

### Requirement: Execution isolation and verified results

集中配置 SHALL 保留独立调用流的排队隔离、取消及迟到结果处理，长补充不得占用 fast 或前台 embedding 通道。同一主备链的文本调用 SHALL 串行，并逐次核对实际模型与该次尝试的预期模型。服务失败按有界切换规则处理，模型身份或业务校验失败不触发备用；链终态失败后沿用原文保存或补充失败规则。本地目标路由不依赖模型，旧 Jev 仅作历史元数据。

#### Scenario: Slow answer and independent work
- **WHEN** deep 补充或后台索引持续运行，同时请求 fast 归类、前台向量查询或本地应用匹配
- **THEN** 独立流不进入同一全局队列，各自期限与取消有效；本地匹配不等待模型

#### Scenario: Mismatched text model
- **WHEN** 主模型或备用适配器返回的实际模型与本次预期不符
- **THEN** 拒绝该响应，停止本次链，不接受任意 Kimi 型号或将其记为主模型成功

#### Scenario: Jev alias resolves to a version
- **WHEN** 历史记录包含旧 jev-latest 别名及对应实际版本
- **THEN** 仅按历史元数据读取和导出，不恢复能力或改写旧记录

### Requirement: Embedding space compatibility

embedding SHALL 返回与输入一一对应、维度正确且数值有效的向量，并暴露稳定的向量空间／处理配置身份供索引校验。文档和查询 SHALL 使用同一兼容配置；更换模型、维度或其他影响向量空间的配置后，不得将新查询向量与旧索引混用。当前索引只支持的维度限制 SHALL 保留，重建不得由一次查询隐式触发。

#### Scenario: Incompatible embedding replacement
- **WHEN** embedding 配置改变，使向量空间或既有索引配置不兼容
- **THEN** 查询报告需要重建或配置不可用，不返回跨空间相似度结果，也不自动清空或重建笔记索引

#### Scenario: Invalid vector output
- **WHEN** 返回向量数量、顺序映射、维度或数值不满足请求约定
- **THEN** 本次结果被拒绝，不写入索引、不作为成功零命中

### Requirement: Diagnostics can be adapted without expanding retention

调用诊断 SHALL 关联能力、逻辑调用、尝试顺序、主备角色、请求及实际模型、切换原因、耗时和最终结果。常规日志不包含正文或密钥。模型模块保留显式内容接收器边界，但当前 Notes 调用 SHALL 不接入完整正文归档；Personal Agent 移除后不得再生成其调试会话。旧归档不主动读取或删除，诊断故障不改变结果，Jev 历史记录不变。

#### Scenario: Generic invocation without archive receiver
- **WHEN** Notes 或向量调用未配置完整内容接收器
- **THEN** 不产生 Personal Agent 归档，正文及认证信息不进入常规日志

#### Scenario: Retired debug archives remain inactive
- **WHEN** 用户保留旧 Personal Agent 调试文件并执行 Notes 主备生成
- **THEN** 不扫描、覆盖或追加旧文件，不创建新 Personal Agent 会话目录；只输出本次有界无正文诊断

#### Scenario: Archive an opted-in Personal Agent call
- **WHEN** 旧偏好仍记录 Personal Agent 已接入完整内容诊断接收器
- **THEN** 当前版本不注册该调用方、不生成新归档，旧 opt-in 不会令 Notes 主备调用写入完整正文

### Requirement: Bounded provider fallback

文字调用 SHALL 仅在超时、网络断连、HTTP 408／429 或 5xx 时按冻结顺序切换一次，主成功不调用备用；备用失败不再重试主模型。取消、配置失效、认证／余额错误、400／422、输入超限、模型身份错误及业务输出错误 SHALL 直接终止。切换前重新检查取消、有效性及剩余期限；无可用备用时保留主失败原因。

#### Scenario: Primary succeeds
- **WHEN** 主模型返回并通过相应校验
- **THEN** 仅发送一次模型请求，不触发备用费用

#### Scenario: Primary is unavailable
- **WHEN** 主调用超时、断连、限流或返回 5xx，备用已配置且仍在期限内
- **THEN** 终止主尝试并仅调用备用一次，使用相同业务资料和约束

#### Scenario: Both providers fail
- **WHEN** 主尝试失败后备用也失败
- **THEN** 只结算一次最终失败，保留可诊断的两次原因；不循环、不并发竞速、不重放外部 action

#### Scenario: Cancellation or invalidation wins
- **WHEN** 主失败与取消、配置失效或范围变化同时发生
- **THEN** 不发起备用，已发起的备用被取消，迟到内容及回调不能被采用

#### Scenario: Non-recoverable failure
- **WHEN** 请求遇到认证、余额、输入约束、模型身份或业务解析错误
- **THEN** 直接报告对应错误，不把不合法输出或错误配置交给备用掩盖

### Requirement: Fallback shares one finite deadline

每个文本调用 SHALL 使用包含本链排队及主备尝试的有限总期限，fast 默认 120 秒、deep 默认 300 秒；业务更短期限优先。备用已就绪时，主尝试最多占 fast 30 秒／deep 120 秒，且不超过出队后剩余预算的一半；备用仅使用剩余预算。无备用时主尝试可用剩余总预算。到期 SHALL 取消工作并丢弃迟到结果，返回不等待无响应的服务；不得对备用重新计满总期限。

#### Scenario: Reserve time for backup
- **WHEN** 默认 fast 主调用持续无响应
- **THEN** 最迟在主尝试 30 秒后转向已就绪备用，主备加本链排队合计不超过 120 秒；DeepSeek 或 Kimi 处于主位置均遵守此规则

#### Scenario: Caller has a shorter deadline
- **WHEN** 上层业务仅剩 20 秒可用于本次 deep 调用
- **THEN** 主尝试最多获得出队后剩余预算的一半，备用只用余额；到业务期限后不发送新尝试、不采用结果

#### Scenario: Late primary completion
- **WHEN** 主尝试超时触发备用后，主请求继续返回文本或最终成功
- **THEN** 不展示主内容、不覆盖备用结果，不额外结算或触发写入

### Requirement: Provider configuration and tests are independent

设置 SHALL 分别管理 DeepSeek 与 Moonshot 密钥并说明主备可能依次接收相同资料及分别计费；每个模型的连接测试仅测试该模型，禁止备用掩盖测试失败。开关、交换及查看状态不发送请求。模型绑定或相关密钥变化 SHALL 使受影响的测试失效，未配置备用显示为降级可用状态而非整个能力不可用。

#### Scenario: Test primary while fallback is healthy
- **WHEN** 用户测试不可用主模型，而备用可正常响应
- **THEN** 测试报告主模型失败，不发送备用请求，也不显示整条链已验证

#### Scenario: Configure one shared Kimi key
- **WHEN** 用户保存 Moonshot 密钥且两个能力均引用 Kimi
- **THEN** 两个型号的配置状态同时刷新，不要求输入两份密钥；界面明确资料发送与账号计费范围

### Requirement: Deep requests use streaming transport

Notes 补充及每周／每月回顾的 deep 主、备请求 SHALL 使用流式传输，即使调用方不展示生成过程也不得等待非流式 HTTP 响应。deep 单模型连接测试 SHALL 验证相同流式协议，并继续只发送测试样例、不使用备用。文字调用 SHALL 保持最终完整结果接口，流式接收不得改变原有资料、格式、token 及字节预算；fast 和 embedding 的默认传输方式 SHALL 保持原值。系统 SHALL 不增加流式设置开关，也不在流式失败后自动重发非流式请求。

#### Scenario: Supplement has no preview subscriber
- **WHEN** Notes 在后台请求补充且没有界面订阅片段
- **THEN** 仍以 `stream: true` 接收主请求及可能的备用请求，完整成功后只向业务返回一份最终文字

#### Scenario: Reverse the providers
- **WHEN** 用户分别使用 Pro → Kimi、Kimi → Pro 或关闭备用执行 deep 生成
- **THEN** 所有实际发送的尝试都使用流式协议，顺序、可用性判断及最多一次切换规则保持有效

#### Scenario: Test a selected deep model
- **WHEN** 用户测试 deep 的一个已配置模型
- **THEN** 仅该模型以流式协议接收固定样例，协议或模型校验失败即报告失败，不调用备用或重新发送非流式请求

#### Scenario: Fast and embedding remain independent
- **WHEN** 同时请求首次标题、归类、已定义的草稿思考提示或向量生成
- **THEN** 不因 deep 流式改造而改变它们的请求模式、预算、排队隔离或启用条件

### Requirement: Stream progress belongs to one active attempt

系统 SHALL 在流式尝试开始时通知调用方重置该次临时预览，并为随后片段关联稳定的逻辑调用与尝试身份。每次发布和实际采用 SHALL 检查取消、当前尝试、业务有效性以及尝试和总期限；无效事件 SHALL 被丢弃。符合既有条件切换备用时 SHALL 先废止主尝试并清除其预览，再发布备用内容，不拼接两家结果。片段 SHALL 仅表示生成中内容，不构成成功结果、缓存或写入授权。

#### Scenario: Show content before completion
- **WHEN** 已核对模型身份的当前尝试收到回答片段，且尚未收到完整结束标记
- **THEN** 调用方可在最终结果返回前收到该尝试的累计回答文字，逻辑调用仍为进行中

#### Scenario: Primary disconnects after partial content
- **WHEN** 主尝试已发出片段，随后断连且备用符合既有切换条件
- **THEN** 主尝试的预览被清除，备用从空预览开始；晚到的主片段或成功不能覆盖备用或造成第二次结算

#### Scenario: Deadline wins over an uncooperative provider
- **WHEN** 尝试已超时、总期限已到或调用已取消，但旧服务仍回调文字
- **THEN** 丢弃这些片段与已排队的界面更新，不延长期限，也不因收到片段延迟超时结算

### Requirement: Stream completion requires verified final output

流式调用 SHALL 在回答片段采用前确认实际模型身份，只采用回答内容，不展示或保存思考过程。只有收到合法的正常结束及完整流终止标记，并通过最终模型、非空和格式约束后 SHALL 返回成功。终止标记前连接结束 SHALL 视为断连并沿用有界切换规则；明确截断、非法事件、工具输出、错误终态顺序及模型身份错误 SHALL 作为不可切换错误终止。网络、配置和取消的既有错误规则及共享期限 SHALL 继续有效。

#### Scenario: Reasoning precedes the answer
- **WHEN** Kimi 先发送思考片段，再发送合法回答及正常结束标记
- **THEN** 思考片段不进入预览或最终输出，回答经校验后正常完成；思考耗时仍占原期限

#### Scenario: Connection ends without final markers
- **WHEN** 已收到部分回答，但连接在完整终止标记前结束
- **THEN** 不返回部分成功，仅在既有规则允许且仍有预算时切换一次备用；没有可用备用则报告失败

#### Scenario: Explicit truncation or invalid model
- **WHEN** 流明确报告 token 截断、包含非法事件或工具输出，或返回模型不符
- **THEN** 停止本次调用并废弃临时结果，不调用备用掩盖输出错误

#### Scenario: Done arrives before a normal finish
- **WHEN** 服务发送 `[DONE]`，但此前没有合法的 `finish_reason: stop`
- **THEN** 将其作为明确的终态格式错误，不误记为网络断连，也不切换备用

### Requirement: Account-owned embedding endpoint

系统 SHALL 不内置工作空间标识、专属服务地址或凭据。用户 SHALL 在 Apple Notes 设置中保存自己的 HTTPS DashScope 向量接口地址和密钥；空地址或无效地址不构成可用配置。保存地址本身 SHALL 不发送请求；更换地址 SHALL 使旧调用失效，并保持既有向量空间校验与显式重建边界。

#### Scenario: Fresh installation without endpoint
- **WHEN** 用户尚未填写向量服务地址，即使本机已有向量密钥
- **THEN** 不发送向量请求；Notes 原文存入与其他已配置文字能力仍可使用

#### Scenario: Change or clear endpoint
- **WHEN** 用户保存自己的合法服务地址或清空地址
- **THEN** 本机保存选择并使旧调用失效，不自动测试；已有索引不能跨服务地址混用，空地址下向量能力不可用
