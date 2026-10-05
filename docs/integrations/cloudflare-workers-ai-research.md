# Cloudflare Workers AI 调用封装调研

> Role: **Reference**
> 官方资料核验：2026-09-26。本文记录外部能力、取舍和待验证边界，不代表已接入或已选定部署方案。

## 结论与适用范围

Workers 可以承担 AI 调用入口：验证调用身份、选择允许的上游和模型、附加服务端密钥、控制请求额度、转发响应。模型仍可使用现有供应商，不必更换为 Cloudflare 的模型。Workers 的 `fetch` 和流式响应能力支持这种薄代理。[Workers 运行机制](https://developers.cloudflare.com/workers/reference/how-workers-works/)、[Streams](https://developers.cloudflare.com/workers/runtime-apis/streams/)

**研究判断：封装调用层有价值，部署在普通 Workers 是否适合中国大陆用户，需要单独实测。** 多一层代理会改变网络路径；V8 isolate 的启动快、全球有节点，都不能直接推出中国大陆端到端响应更快。应比较直连、Workers，以及靠近目标用户或上游的同协议服务端。

## 三个产品分别解决什么

| 产品 | 作用 | 本场景用途 |
|---|---|---|
| Cloudflare Workers | 运行自己的服务端代码 | 实现 Jotway 的身份、额度、路由和协议边界。[运行机制](https://developers.cloudflare.com/workers/reference/how-workers-works/) |
| AI Gateway | 管理模型调用，提供分析、日志、缓存、限流、重试和 fallback | 需要现成观测与治理时可接入；DeepSeek 有官方接入说明。[概览](https://developers.cloudflare.com/ai-gateway/)、[DeepSeek](https://developers.cloudflare.com/ai-gateway/usage/providers/deepseek/) |
| Workers AI | 在 Cloudflare GPU 上运行模型 | 属于更换或新增模型来源，应另评估模型质量、价格和时延。[概览](https://developers.cloudflare.com/workers-ai/) |

建议先比较 `客户端 → Worker → 当前供应商`。有明确观测需求时再考虑 `客户端 → Worker → AI Gateway → 供应商`；额外能力与路径应单独测量，不作为第一阶段必选项。

## 响应速度由哪些部分决定

可把首个有效内容的等待时间拆成：客户端接入时间、代理检查时间、代理到上游的网络时间、模型等待/计算时间，以及返回路径。普通 JSON 请求还需等完整结果；SSE 请求可以先送出已有内容。这是分析模型，不是测量结果。

- **冷启动：** Workers 使用 V8 isolates，复用已有运行时，避免每次启动虚拟机或容器的那类开销。官方同时说明 isolate 可能被回收；不能据此承诺所有请求启动耗时为零。[运行机制](https://developers.cloudflare.com/workers/reference/how-workers-works/)
- **流式透传：** Worker 可以直接返回上游 `Response` 或以 `upstream.body` 创建响应，无需读完整正文。调用 `await response.text()` / `.json()` 后再返回会把完整响应缓冲起来；如需修改流，用 Streams API。[Streams](https://developers.cloudflare.com/workers/runtime-apis/streams/)
- **CPU 与等待不同：** 等 `fetch()`、数据库和网络 I/O 不计入 CPU time；HTTP 请求在客户端保持连接期间无硬性 wall-time 上限。因此模型生成几十秒，不等于 Worker 消耗几十秒 CPU。[Limits](https://developers.cloudflare.com/workers/platform/limits/)
- **连接生命周期：** 客户端断开后工作可能被取消；流式响应仍在传输时无需用 `waitUntil()` 续命。`waitUntil()` 在响应结束或断开后最多延长 30 秒。[Context](https://developers.cloudflare.com/workers/runtime-apis/context/)

**实现建议：** 热路径保持一次上游请求，限制请求大小，保留状态码和必要响应头，保持 SSE 分块传输；记录状态、耗时和用量元数据时避免同步写入远程数据库。总超时、取消、流中断和重试需要贯穿客户端与代理；已经返回部分输出后不要透明重发模型请求。

## Placement 如何选

| 配置 | 官方行为 | 研究判断 |
|---|---|---|
| 默认 | 在接近请求进入位置的数据中心执行 | 适合作为薄代理基线；接近入口不等于接近中国大陆用户或模型机房 |
| `placement.mode = "smart"` | 按观测到的 Worker/上游耗时选择位置，把额外转发耗时纳入比较 | 可列为对照组；一次上游调用未必受益 |
| `placement.region` | 选择最接近指定 AWS/GCP/Azure region 的 Cloudflare 机房 | 只有掌握真实上游区域时才有针对性；不是部署进该云区域 |
| `placement.host` / `hostname` | 探测目标端点后选择附近位置；host-based placement 为实验能力 | 单一固定上游可评估；不要仅凭 API 域名猜物理区域 |

Smart Placement 的分析可能需 15 分钟，只考虑 Worker 曾运行过的位置，流量不足可能无法形成决策；默认保留 1% 未经 Smart Placement 的请求用于对照。对于刚开始、流量较小的项目，不能把“已开启”当作“已优化”。以上行为见 [Placement 官方文档](https://developers.cloudflare.com/workers/configuration/placement/)。

## 密钥、鉴权、限流与日志

供应商共用密钥适合放在 Worker Secrets，通过 `env` 读取；不要存入源代码或普通配置变量。[Secrets](https://developers.cloudflare.com/workers/configuration/secrets/)

以下是面向发布客户端的设计建议：

1. App 使用可撤销的用户/设备凭证调用自己的接口，Worker 校验身份后使用供应商密钥。把一个永久共享代理口令写进所有客户端，无法实现可靠的用户隔离和额度归属。
2. 服务端固定允许的上游、路径和模型，限制输入长度、输出 token 与并发，避免成为任意网址转发器。身份 ID 必须来自已验证凭证，不能直接相信请求里的 `userId`。
3. 分开“短期请求限流”和“金额/用量硬额度”。内置 Rate Limiting binding 的计数是每个 Cloudflare location 独立、异步更新，不是全球精确账本；适合抑制突发流量。严格共享额度需另做一致性控制。[Rate Limiting](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/)
4. 若接入 AI Gateway，不要给每个 App 下发账号级 Cloudflare API token。官方说明 `AI Gateway Run` 权限无法限制到单个 gateway；Worker binding 可在账号内预认证。[Authenticated Gateway](https://developers.cloudflare.com/ai-gateway/configuration/authentication/)
5. AI Gateway 默认启用日志，日志可含 prompt 和 response；对草稿文本应明确关闭正文收集或整个日志，并仅保留必要元数据。默认设置不是隐私承诺。[Logging](https://developers.cloudflare.com/ai-gateway/observability/logging/)

若用户自带供应商 Key（BYOK），让 Key 经过自己的服务端会新增信任和处理边界；是否值得中转，需由统一能力、用户地域和实测收益决定。

## 成本与运行限制

以下为核验时标准 Workers 价格，模型供应商费用另计；不要把 Workers、Workers AI 和 AI Gateway 的费用混为一项。[Workers Pricing](https://developers.cloudflare.com/workers/platform/pricing/)

| 项目 | Free | Paid / Standard |
|---|---|---|
| 基础费 | $0 | 账号至少 $5/月 |
| 请求 | 100,000/日 | 含 10,000,000/月；超出 $0.30/百万 |
| CPU | 每次 10 ms | 含 30,000,000 CPU ms/月；超出 $0.02/百万 CPU ms |
| HTTP 持续时间 | 不按时长收费 | 不按时长收费 |
| 流量 | 无额外 egress / bandwidth 费 | 无额外 egress / bandwidth 费 |

付费 HTTP 请求 CPU 默认上限 30 秒、可配置至 5 分钟；内存 128 MB，单次请求最多 6 个同时出站连接。薄代理仍需按真实鉴权与解析负载验证免费档 10 ms 是否足够。[Limits](https://developers.cloudflare.com/workers/platform/limits/)

AI Gateway 的基础分析、缓存、限流目前免费；Guardrails 等能力另有费用。**2026-09-24 起首次创建 gateway 的新客户，日志采用 Workers Logs 的计费和保留规则**；旧客户的持久日志规则不同。Unified Billing 购买额度收取 5% 费用，因此不能概括为“所有网关能力完全免费”。[AI Gateway Pricing](https://developers.cloudflare.com/ai-gateway/reference/pricing/)

## 尚未由官方资料回答的问题

- 目标中国大陆运营商、时段、代理状态下，Worker 比直连快还是慢。
- 当前供应商从 Cloudflare 出口访问时的实际区域、稳定性和限流差异。
- 已选定鉴权、额度存储、日志和网关功能后的 p50/p95 端到端耗时。
- 当前 Jotway 经过候选代理后的耗时分布，是否需要调整超时、并发和流式消费；下文给出代码中的预算基线。

这些需要端到端试点，不以节点数量、CPU 平均值或一次 `curl` 的 HTTP 首字节时间替代模型首个有效内容与完整结果的测量。

## 中国大陆网络的部署判断

用户主要关心中国大陆访问速度。普通 Workers 的全球部署不能等同于自动使用大陆节点：Cloudflare China Network 是 Enterprise 客户另购的订阅；当前产品列表确实包含 Workers，因此也不能笼统说 Workers 不支持大陆部署。[China Network](https://developers.cloudflare.com/china-network/) · [可用产品](https://developers.cloudflare.com/china-network/reference/available-products/)

**推断与建议：** 当请求经过境外入口、再访问境内上游时，可能比现有直连多出跨境绕行；如果原先直连海外上游的链路差，代理也可能改善结果。官方资料不能推导出特定运营商、时段、模型的固定增加毫秒数。自定义域名便于维护入口，但不会仅因换了域名就获得大陆节点或改变回源路线。

因此，应把“统一 AI 接口”与“选 Cloudflare 托管”拆开：同一份客户端协议可以由 Workers 或其他区域的后端实现。大陆部署可作为与 Workers 对照的候选；香港也需要跨境实测，不能按地理距离预判胜负。这是待测部署选项，不是已确定的架构决策。

## Jotway 的适配边界

以下是调研时的代码观察；当前产品行为仍以 [AI capability](../plugins/ai.md) 和 [Jev intent recognition](jev-intent-research.md) 为准。

| 调用路径 | 已有实现 | 对代理的意义 |
|---|---|---|
| Jev 意图识别 | [Jev.swift](../../Sources/Integrations/Jev.swift) 的请求/资源超时为 1.5 秒；[IntentRecognition.swift](../../Sources/Features/Launcher/IntentRecognition.swift) 默认先防抖 500 ms | 500 ms 防抖不属于 1.5 秒网络超时。新增链路更易耗尽网络预算；应独立评估，不因文本整理可用就一起迁移 |
| 通用 AI transport | [OpenAICompatible.swift](../../Sources/Integrations/OpenAICompatible.swift) 设置 `stream: false`，用 `URLSession.data(for:)` 收完整响应，超时 120 秒 | Worker 支持 SSE 不会自动使客户端逐字显示；当前重点是完整结果耗时 |
| 存入前整理 | [BundledActions.swift](../../Sources/Actions/BundledActions.swift) 单独构造固定 DeepSeek 的 processor；[AITextProcessor.swift](../../Sources/Actions/AITextProcessor.swift) 在失败时回退原文 | 只改设置页的通用 provider 不一定覆盖这条路径；提醒和日历仍要完整结构化结果才能创建 |
| 模型与排队 | [AIProviderPlugin.swift](../../Sources/Plugins/AIProvider/AIProviderPlugin.swift) 在每个 actor 实例内串行调用，校验请求模型与返回模型一致 | 后端偷偷换模型可能触发拒收；代理不会消除客户端排队 |
| 提前准备 | [ActionExecutor.swift](../../Sources/Actions/ActionExecutor.swift) 默认防抖 500 ms 后准备，并复用同一输入的结果 | 网络总耗时与按 Enter 后剩余等待不同，应分别记录 |

若目标是集中管理 Key，客户端持有自己的服务访问凭证，Worker 持有上游 Key；若继续让用户自带 Key，则密钥归属、转发说明与鉴权策略不同。给所有安装包写入同一个长效“代理密码”不构成可靠的用户身份体系。

最低改动的试点是让 DeepSeek 的请求协议和返回模型保持一致，仅新增自己的代理来源与鉴权适配，并覆盖 action processor 的构造入口。若要统一提示词、自由切换模型，可以再引入按用途定义的 API，例如 `/v1/text/process`，显式约定正文、mode、风格、当前时间/时区、实际模型、协议版本和错误；时间上下文应来自用户设备，不能改用 Worker 的默认时间解释“明天下午”。这些是可选适配方式，本次未实现。

## 接入操作参考

1. 用官方 C3 创建独立 Worker 项目：`npm create cloudflare@latest -- jotway-ai-proxy`；先选择不部署，通过 `npx wrangler dev` 本地验证。无需给 Swift 项目增加 Cloudflare SDK。[CLI 入门](https://developers.cloudflare.com/workers/get-started/guide/)
2. 在 Worker 定义固定路由和允许的模型/上游，校验客户端凭证、请求大小与输出上限，转发 JSON 或 SSE，保持取消、超时和状态码的清晰约定。
3. 通过 Secrets 保存上游 Key，例如 `npx wrangler secret put DEEPSEEK_API_KEY`。此命令会产生并立即部署新版本，应在实际部署流程中使用；本地密钥放入被 Git 忽略的本地 secrets 文件。[Secrets](https://developers.cloudflare.com/workers/configuration/secrets/)
4. 实际发布使用 `npx wrangler deploy`。可绑定自己控制的子域名；Custom Domain 要求 active Cloudflare zone，并由 Cloudflare 配置 DNS 和证书。文中的名称只是示例，不表示已拥有域名。[CLI 入门](https://developers.cloudflare.com/workers/get-started/guide/) · [Custom Domains](https://developers.cloudflare.com/workers/configuration/routing/custom-domains/)
5. 客户端增加可切换的代理配置，先对照验证文本整理，再独立评估 Jev；公开提供统一 AI 服务时，再落实用户身份与额度规则。

## 如何测出是否影响速度

以下是建议的测量方法，不是已获得的测试结果：

- 对照直连与 Worker；若考虑其他区域后端，用相同协议作为第三组。保持模型、提示词、输出长度、stream 设置和并发一致，不开启响应缓存、自动重试或自动换模型，以免混淆结果。
- 从目标大陆用户网络交错发送 A/B 请求，覆盖移动/联通/电信中的实际目标网络及高峰、低峰；先用每组约 30–50 次作初筛，数量不足以对稀有故障或 p99 作强结论。
- 分开记录新建连接和复用连接；记录中位数、p95、失败率、超时率。Jev 另看在 1.5 秒网络预算内拿到可用建议的比例；文本整理看完整结果与按 Enter 后等待。
- 若以后支持流式，测“首个有内容的 token”，不能拿响应头、SSE keep-alive 或空白 chunk 的 TTFB 代替；同时记录生成完成时间。
- 利用现有 `queueDurationMs`、`durationMs`、`totalDurationMs` 区分客户端排队和网络调用；Worker 侧记录鉴权耗时、上游首响应、结束状态、请求 ID 和实际执行位置，不记正文或 Key。
- 对取消、超时、429、上游错误分别验证；客户端断开与上游停止生成/停止计费并非同一事实。Workers 的 Request 文档说明了 `signal` 与 `enable_request_signal` 兼容设置，需按所选 compatibility date 配置和实测。[Request API](https://developers.cloudflare.com/workers/runtime-apis/request/)

本次仅核查代码和官方资料，没有部署 Worker，也没有调用付费模型或获得大陆真实 A/B 数据，不能据此承诺增加多少毫秒。
