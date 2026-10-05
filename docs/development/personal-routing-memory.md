# 个人路由记忆实施方案

> Role: **Work**
> 状态：暂停的候选方案；尚未实现或派发。当前行为以 [Jev intent recognition](../integrations/jev-intent-research.md) 为准。
>
> 当前推进范围是[当前本地操作记录](data-model.md)：用户手工维护 Local Rules，操作记录仅用于本机复盘和导出。下文自动学习、独立案例表以及保留旧反馈表的设计均未获实施，本轮不执行；恢复此方案前须按统一记录重新评审，不能直接沿用旧采样/存储章节。

## 场景与交付范围

用户希望 Jotway 从显式选择中逐渐理解自己的表达：把“这个回头看”交给 Apple Notes；把解释类问题从 Chrome 改选 ChatGPT 后，同类输入能得到更符合习惯的建议。

分两段交付，共用一份有界的本地案例数据：

- **A：同一句话记得住。** 确认一次显式选择后，再输入同一完整表达，在无更高优先级指令时可以采用该选择；具备关闭、删除、冲突更新与失败恢复能力。
- **B：换一种说法也能用。** 经过中文语义评估后，从多个独立案例推广到相似表达。A 不能被描述为已完成 B；“这个回头看：文章甲”与“这篇文章留着以后看”属于 B 的验收范围。

第一版只学习已注册 action 的选择，包括 ChatGPT，且不依赖目标是否声明 Jev model binding。目标仍须可执行，Enter 或现有确认按钮才执行。输入与模型均不自行执行 action。

非目标：用户画像、长期内容检索、会话历史、习惯时间推断、自动改写偏好、多设备同步、模型微调、云端记忆、任意应用的语义启动。现有应用使用统计继续负责本地应用匹配。

## 当前实现与必须补齐的缺口

| 入口 | 当前行为 | 实施要求 |
|---|---|---|
| `LauncherSession.confirm` | 有当前 Jev action 建议且显式改选时才写纠正 | 从最终确认上下文记录主动选择，覆盖无 key、无建议及按钮确认 |
| `finishSetup` | 配置完成会程序化设置 `explicitTargetID` | 区分用户选择与配置完成，不能把 `.explicit` 一律当学习证据 |
| `submit` | 清空编辑器可能被拒绝；之后才创建执行任务 | 冻结确认上下文，通过提交接受检查后才写学习样本 |
| `IntentRecognition` | 本地应用匹配与 Jev 共用 suggestion；本地拒绝会阻止 Jev | 对外区分本地应用的无匹配、匹配与拒绝，保持既有行为 |
| `RouteResolver` | 唯一的纯值路由优先级实现 | 在此合并个人建议，不另写一套 Session 路由逻辑 |
| `IntentCorrection` / `IntentFeedback` | 纠正与采用诊断，缺少完整选择来源和重试身份 | 保留语义；不直接用作学习样本，不自动回填 |
| `ChatGPTModule` | `modelBinding == .conversation`，Jev 可建议普通对话请求 | 个人建议从 registry 的可执行 action 选择，独立于 Jev 的候选协议 |

相关实现：[LauncherSession](../../Sources/Features/Launcher/LauncherSession.swift)、[RouteResolver](../../Sources/Features/Launcher/RouteResolver.swift)、[IntentRecognition](../../Sources/Features/Launcher/IntentRecognition.swift)、[IntentFeedbackMapping](../../Sources/Features/Launcher/IntentFeedbackMapping.swift)。

## A：可信样本与精确表达记忆

### 采样契约

在 Session 中给显式选择附加来源：`userChoice` 或 `setupCompletion`。只有用户的 `selectTarget` / `cycleTarget` 产生前者；编辑使选择失效时同步清除此来源。

首次手动选择时冻结用户当时看到的自动目标及来源，保留到该正文的最终确认；后续迟到的 Jev 结果不能改写“用户纠正了什么”。选择过程中来回切换只产生一次最终证据。即使最终选回原建议，只要实际主动选过，也可记录为明确选择。

确认时冻结正文、选择和身份；最终目标通过 registry 可用性检查，且 `clearDraft()` 成功并创建执行任务后，才提交学习事件。写库不阻塞执行。外部 action 失败不代表选择错误，不撤销案例，也不产生反向偏好。

以下情况不产生学习样本：

- 只输入、切换后取消、隐藏面板、进入或完成 Setup 而未主动选择。
- 被动确认 Jev、个人建议、关键词或默认 action。
- 尚在中文组字、最终目标不可用、原生编辑器拒绝提交。
- 纯应用启动、Setup 目标、超出学习正文上限的输入。

现有 Jev 采用与纠正诊断可以继续记录；个人学习不伪装成 Jev adoption。

### 数据与重试身份

追加新的数据库迁移，名称按落地时已有迁移顺序确定；不修改 `v1_launcher`。新增 `personal_routing_examples`：

| 字段 | 用途 |
|---|---|
| `id` | 稳定案例 ID |
| `lineageID` | 一次草稿及其失败恢复链的身份 |
| `textDigest`、`normalizationVersion` | 完整正文最小归一化后的摘要与算法版本 |
| `text` | 确认时的原文，供匹配与用户查看；摘要不是匿名化措施 |
| `chosenTargetID` | 最终选择的 action 稳定 ID |
| `shownTargetID?`、`shownSource?` | 第一次主动切换前实际展示的目标及来源，允许为空 |
| `selectionOrigin`、`confirmationSource` | 选择来源和 Enter / Command-Enter / 按钮确认 |
| `confirmedAt`、`updatedAt` | 首次确认与最近一次目标更新的时间 |

唯一键为 `(lineageID, normalizationVersion, textDigest)`，不包含 revision、目标或建议 UUID。同正文同目标的失败重试为幂等操作，不增加计数或刷新时间；重试时主动改选另一个目标更新同一案例。摘要匹配后还需比较归一化正文。

`FailedSubmission` 携带 lineage：恢复到空稿时保留旧 lineage，合并到已有新稿时使用新 lineage。不要只依赖 `draft.id`：当前自动恢复和手动恢复对它的处理不同。重新输入内容形成新稿可以产生新案例，但 B 统计独立证据时相同归一化正文只计一份。

建议 v1 默认：学习开关开启，案例本地保存最近 500 条且距 `updatedAt` 最长 90 天，正文最多 4,096 UTF-8 字节。以上是有界产品默认值，不是准确率结论。超长输入正常执行但跳过学习，不能截掉尾部后学习。读取、写入及启动加载时都排除过期记录，并清除过期数据及派生缓存；同目标失败重试不刷新 `updatedAt`。

旧纠正缺少 lineage 和可靠选择来源，可能混入重试或配置产生的显式选择；旧采用记录也不是独立偏好。不自动导入这两类记录，清空后更不能再从旧表重建记忆。

### 精确匹配与冲突

第一阶段只做完整正文匹配。归一化限于首尾空白、换行形式与 Unicode canonical normalization；保留大小写、内部标点、否定、日期、URL、路径和正文顺序，不自动抽取前缀或删除实体。

对同一归一化正文采用最近一次有效主动选择，用户再次明确改选后下次即可更新。目标暂不可用时该偏好休眠，继续走普通路由；不能跳到更旧的另一个目标。删除一个表达时移除其全部案例；A 对该表达不再有建议，B 从剩余表达重新计算。

精确匹配不依赖 Jev key、网络或语义模型。无案例时返回无建议。

## B：相似表达的语义匹配

### 模型选型先做可运行验证

优先评估 Apple `NLEmbedding.sentenceEmbedding(for:)`，但其返回值可为 `nil`，必须按实际可用性降级。`NLContextualEmbedding` 支持中文并不直接证明它适合句子相似度，Apple 对相似度任务另指向 `NLEmbedding`；模型资产也可能尚不可用。[句子模型返回契约](https://developer.apple.com/documentation/naturallanguage/nlembedding/sentenceembedding(for:))、[Contextual embedding](https://developer.apple.com/documentation/naturallanguage/nlcontextualembedding)

系统模型不可用或质量不足时，离线对照候选为 `intfloat/multilingual-e5-small`。其模型卡说明输出 384 维，非检索任务可统一使用 `query: ` 前缀，长文本最多处理 512 tokens；它只是候选，尚未验证 Swift 推理、Core ML 转换、分词一致性、资源体积或路由质量。[作者模型卡](https://huggingface.co/intfloat/multilingual-e5-small/raw/main/README.md)

选型必须实际检查：中文同义改写、中英混写、否定与引用、同主题不同操作、资产缺失、macOS 15 支持和声明支持的处理器架构、冷启动/热调用耗时、常驻内存与安装资源体积。若采用转换模型，校验分词、pooling 和归一化与原始实现的一致性，并固定模型版本及资源校验值。

不得因为 embedding 得分高就宣称意图相同；不得使用固定通用的“0.8 即正确”阈值。模型评估未通过时保持 A，B 不标为完成。缺资产时不在输入热路径自动下载，不把历史正文改发给云端代替本地匹配。

### 检索与决策

只对完整可编码、未超过模型 token 上限的正文计算向量；会被截断的输入退出语义匹配，A 仍可用。只比较相同模型、分词和归一化版本生成的向量。第一版可从有界样本重建内存向量，无需专用向量数据库。

初始算法作为待评估配置：

1. A 未命中时，在本地召回最多 8 个最相近的不同表达；同一归一化正文先保留最新有效明确选择。
2. 按目标分组，每个目标最多取 3 个最相近案例，结合相似度与时间衰减评分，防止常用 action 靠总量占优。
3. 跨表达推荐至少需要 3 个不同表达支持同一目标；同时满足最低相似度、与第二目标的差距及冲突限制。30 天半衰期可作评估初值，所有数值连同算法版本统一管理。
4. 有高相似反例、否定/引用/多目标等未能区分的输入，返回无个人建议。相似度无法区分操作时，要缩小适用范围或补充本地意图判别，不能仅降低阈值提高覆盖率。
5. 输出目标、依据案例 IDs、精确/语义来源和内部评分。分数不作为“正确概率”展示；日志不写正文、向量或完整案例。

首次实现先在离线回放中比较，不立刻接管用户路由。校准集与评估集按表达模板/主题分组拆分，避免同一句改写同时用于调参和评估。验证集同时包含 Notes、ChatGPT、Chrome、Reminders、Calendar 的正确路由与应放弃推荐的场景。

建议启用门槛：相对于无个人记忆基线，持出样本上的改选次数下降；实际给出个人建议的样本精确率至少 95%；关键反例无误覆盖；同时报告建议覆盖率与样本量，不能靠始终不建议通过。它是发布门槛，尚无实测结果。语义模型未定前不承诺具体准确率或时延。

## 模块接口与唯一的路由接入

新增 `PersonalRoutingMemory` module，生命周期由 `AppState` 管理。它接收既有 `LauncherStore`，隐藏归一化、案例查询、去重、过期清理、匹配和派生缓存。首版使用具体依赖，不引入可插拔 provider 框架。

Interface 只覆盖业务操作：`observe(confirmedChoice)`、`suggest(query)`、`examples()`、`forget(selection)`、`setEnabled(value)`；`forget` 可表示同一表达的全部案例或全部学习案例。管理操作返回成功/失败及新的记忆 revision。语义推理和数据库 I/O 离开 MainActor；UI 更新保持 MainActor。

Session 接收一个只含有效结果的建议值：`targetID / evidenceIDs / matchKind / snapshot / validUntil`。RouteResolver 只消费该值，不读库、不算向量。新增 `.personalMemory` 路由来源，优先级固定为：

1. 本次显式选择。
2. 用户保存的短语规则。
3. action 本地关键词。
4. 有效的本地应用匹配。
5. 有效的个人记忆建议。
6. 当前有效的 Jev 建议。
7. 默认 action → Notes Setup → 不可用说明。

保留本地应用的全部既有判定，不改变短前缀、常用度或歧义语义。本地应用判定为拒绝时，跳过个人记忆和 Jev，维持原来的 fallback / 手动选择路径。个人建议不返回 `app_*` 或 Setup；不可用的个人目标被忽略，显式选择不可用时仍保留选择并报错。

`IntentRecognition` 暴露既有本地应用判定值，避免 Session 重复计算。Jev 的请求与结果协议不需要更改；个人记忆 revision 独立于 Jev 配置 revision。学习样本和向量留在本地，当前草稿仍按既有 Jev 配置发送。

个人建议快照包含 `draftID / revision / panelSession / registryRevision / memoryRevision / matcherVersion`，以及当前正文和可执行目标集合。输入改变、组字、隐藏、Setup、提交、记忆或算法变化时取消任务并清除旧建议；异步返回同时验证 generation 与快照。删除不能被迟到计算或尚在排队的写入撤销。

`validUntil` 不晚于任何依据案例的到期时间；B 还设短的重算期限以更新时间衰减。Session 在展示与确认前校验时效，并安排到期失效/重算；过期时即时回到其他有效路由，不等待匹配完成。传给纯值 RouteResolver 的有效性已包含时效判断，不能只比较 revision。

个人结果变化主动触发 Session 的 render，不依赖 Jev 的 changed 回调。显示、候选顺序、预热和确认仍消费同一 `RouteDecision`。`ActionExecutor` 已能在目标改变时替换未提交预热，原则上无需修改；已确认提交取得的执行任务不受删除记忆影响。

## 管理、删除与呈现

在 Intent Recognition 设置加入独立的 “Learn from my choices” 开关与案例管理，说明本地保留的范围和期限；不要求 Jev key。当前界面保持英语，中文例句属于用户输入。

- 关闭：立即停止使用和新增学习样本，取消在途匹配；保留已存样本供查看或删除。重新开启不回填关闭期间的输入。
- 单条删除：按完整归一化表达分组呈现，删除该表达的所有案例，避免隐藏的重复案例让它立即复活。
- “Clear learned choices”：清除新学习表与全部派生索引；不影响用户手工短语规则或应用使用统计。明确它不删除旧的意图诊断正文。
- 另提供 “Clear all intent data”：同时清新表、旧 `intent_feedback` 与 `intent_corrections`，保留手工规则。因为旧反馈也包含正文，不能用仅清新表的按钮声称删除了全部意图数据。

写入、删除和清空使用同一串行协调入口及 epoch；已排队的旧事件与旧计算不得在清空后回写。关闭也使关闭前排队的学习事件失效，重新开启不得重放它们。旧纠正的删除不能继续绕过异步写队列。删除结果成功后才更新列表；失败显示错误并维持停止使用旧建议的状态，直到刷新或重试完成。

最终路由来源为 `.personalMemory` 时展示 “Based on your previous choices”，放在独立 provenance 状态中；不要复用异步识别状态或错误消息。手动改选、回退、删除后立即消失。个人建议已生效时，不把后台 Jev 的 “Recognizing…” 当主提示。支持完整 accessibility label 和 tooltip。

## 实施顺序与文件

| 顺序 | 工作 | 主要文件 | 完成标志 |
|---|---|---|---|
| 1 | 确认事件、来源、lineage、有界持久化和删除 | 新增 `Data/PersonalRoutingExample.swift`；`Database.swift`、`IntentFeedback.swift`、`LauncherSession.swift` | 无 Jev 也能记录；重试与 Setup 不制造假证据；清空不复活 |
| 2 | A 的完整匹配及路由 | 新增 `Features/Launcher/PersonalRoutingMemory.swift`；`RouteResolver.swift`、`IntentRecognition.swift`、`AppState.swift` | 同句显式改选能影响下次，既有优先级不退化 |
| 3 | 设置、提示及 A 验收 | `JevSettingsView.swift`、`LauncherViewState.swift`、`EditorView.swift`、英语 strings | 可关闭、删除、清空，当前建议即时失效 |
| 并行调研 | B 模型与离线回放 | 临时 CLI 探针和评估样本；通过后再确定模型资源/运行时文件 | 中文质量、运行环境、分词和资源预算有实测 |
| 4 | 接入经验证的 B | 个人记忆 module 内部及所选本地模型实现 | 同类新表达改选减少，反例与过期结果验证通过 |

目前工作区有并行的 action、设置和文档修改；实施前重新检查 `git status` 与相关 diff，沿用最新 action contract。不要覆盖已有改动，不因本方案顺带更换 ChatGPT 路径或整理 action 设置。

## 验证与验收

A 必须覆盖：

1. 无 Jev key 时，输入未命中规则、关键词或应用名的“帮我解释一下这个原理”，主动选择 ChatGPT 并确认；重启后同句建议 ChatGPT，按钮与键盘确认一致。
2. 同句再次改选 Notes，下一次更新为 Notes；被动按 Enter 不增加独立证据。
3. 规则、关键词、本地应用匹配优先；歧义应用输入不被个人记忆接管。
4. 取消、Setup 自动选择、中文组字及编辑器拒绝提交均不训练。
5. 外部执行失败保留选择，自动/手动恢复到空稿后重复提交只算一条，改选更新同一条；合并新稿按新正文处理。
6. 禁用或卸载目标时回退；重新可用可恢复使用，明确选择不可用仍报错。
7. 关闭、过期、单条删除和清空后，在途建议与排队写入都不能复活；清空所有意图数据覆盖旧表。
8. 迁移后旧数据仍可读取；写库失败不阻止执行、不泄露正文，用户管理失败有反馈。

B 额外验证：多条“留着以后看”的明确 Notes 案例支持新表达；多条解释类 ChatGPT 案例支持另一主题的解释问题；“明天提醒我看”、明确搜索、引用指令、否定与多目标不因主题相近误路由。长文本不通过截断伪装高把握，混合语言和缺资产情况能降级。

实施后运行 `swift build` 和相关现有测试。可复用 `LauncherActionTests`、`IntentRecognitionTests`、`IntentCorrectionTests`、`IntentFeedbackTests`、`JevPanelTests` 与 `MainPathTests` 的内存存储和依赖注入。没有现成覆盖的行为用临时最小 CLI / 离屏用例验证；遵循仓库要求，不未经用户要求新增测试文件。构建使用项目要求的工具链；若环境版本不同，明确报告验证范围。

默认不启动已安装的 Jotway。真实窗口的 360/560 pt 宽度、长文案、深浅色、中文组字与删除后的提示变化列为人工验收；若后续用户明确要求自动 UI 验证再执行。

A 单独交付时只把 A 的已实现行为合并入 Current docs，保留本文中仍在推进的 B 并删去完成段落；全部完成后更新路由、数据和设置的 Current 文档并删除本 Work 文档。验证日志留在提交或交接，不进入 Current。
