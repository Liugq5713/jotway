# Superpowers OpenSpec 与 YorZ 的方案工作流比较

> Role: **Reference**
> 调研日期：2026-10-09

针对「写方案 → Multica 派发 → fork review → 合入」和已有五段模板，建议先借用 Superpowers 的计划质量检查。需要长期维护行为规格时再考虑 OpenSpec；需要在同一文档持续恢复执行状态时，YorZ 更对口。这是结合当前仓库约定的适配判断，不是工具效果排名。

## 三者解决的问题

三者范围不同：`writing-plans` 是 Superpowers 中的实现计划 skill；`openspec-propose` 是 OpenSpec 的提案入口；本机 `yorz-spec` 覆盖方案、任务和执行状态。不能把完整框架的能力全部算在某一个 skill 上。

| 对象 | 主要优势 | 主要代价 |
| --- | --- | --- |
| Superpowers writing-plans | 精确到文件职责、接口签名、任务依赖与验证结果；方便把代码工作交给另一位 agent。 | 输入通常已有规格；偏编码执行，默认 TDD 与频繁提交，需适配仓库规则。 |
| OpenSpec openspec-propose 及配套流程 | 区分变更意图、行为约定、设计与任务；差量规格可回灌长期规格。 | 默认多份材料需要同步；依赖 CLI 和项目初始化；定制也有维护成本。 |
| 本机 yorz-spec | 单文档保留阶段、批注、任务和执行记录，适合中断恢复。 | frontmatter、标题、批注和 lint 有固定约定；自动推进与完成语义需要理解。 |

## 已核实的能力和边界

**Superpowers** 要求先划分文件职责，再拆出可独立验证的任务，写明消费和产出的接口。计划完成后，作者自行检查规格覆盖、类型一致性、遗漏场景与篇幅；这不是独立 reviewer。当前版本强调写清实现者不能自行决定的事项，不要求预写全部实现代码。默认步骤包含先失败的测试、实现、通过测试和提交；实现前先让用户审阅计划。[writing-plans 源码](https://github.com/obra/superpowers/blob/main/skills/writing-plans/SKILL.md)

**OpenSpec** 的 propose 只生成规划材料。默认 schema 包含 proposal、差量 specs、design 和 tasks；design 按条件创建，任务必须说明完成的验证方法，未强制采用固定的红绿测试循环。独立的 apply 才进入实现，sync/archive 负责把差量同步到当前规格。[propose 源码](https://github.com/Fission-AI/OpenSpec/blob/main/skills/openspec-propose/SKILL.md)、[默认 schema](https://github.com/Fission-AI/OpenSpec/blob/main/schemas/spec-driven/schema.yaml)、[入门流程](https://github.com/Fission-AI/OpenSpec/blob/main/docs/getting-started.md)

OpenSpec 可以用项目规则注入约束，也可以定制 schema 的产物、模板与依赖；官方给出仅 proposal 和 tasks 的轻量示例。因此「默认偏重」成立，「只能采用固定四份文档」不成立。要支持五段格式，可以定制模板，但这比直接采用 Markdown 模板多一层配置。[定制文档](https://github.com/Fission-AI/OpenSpec/blob/main/docs/customization.md)

**YorZ** 以 Markdown 为状态来源，按 `plan → tasks → execute → done` 推进；任务含动作、对象和验收点，执行后持续回写。新增范围会重开 plan。GUI/Service 可选，但 skill 要求每次写回后运行 `yorz lint`；tasks 无阻塞时会继续执行。尤其要注意：未完成的 `[manual]` 项不阻止 `done`，所以 done 不代表人工验收完成。本地工作流的 skill 与阶段规则

## 对 Jotway 的选择建议

1. **现在先借用 writing-plans 的内容检查。** 保留已有五段结构，增加精确入口、跨任务接口、验收对应关系和遗漏场景检查；验证使用既有测试、构建或明确的人工操作。仓库规定未被要求时不新增测试，因此不能照搬默认 TDD 步骤。[五段模板](ai-development-plans-research.md#建议试用的五段模板)、[仓库规则](../../AGENTS.md)
2. **长期规格维护成为问题时采用 OpenSpec。** 差量同步适合持续演进的行为约定，但需先确定它与现有 Current 文档的归属，避免两份真相。仓库要求完成后回灌 Current 并删除 Work，与 OpenSpec 默认保留 archive 的生命周期需要协调。[仓库文档约定](../../AGENTS.md)、[归档行为](https://github.com/Fission-AI/OpenSpec/blob/main/docs/getting-started.md#what-happens-on-archive)
3. **频繁恢复执行上下文时再采用 YorZ。** 单文档状态有价值，但要适配「先审方案、再派发」的交接边界，明确区分机器任务完成与人工验收。2026-10-09 本次 shell 的 `command -v yorz` 与 `command -v openspec` 均未找到命令，只说明当前 PATH 不可调用，不能推断整机未安装。

## 如何判断方案真的有用

使用同一个真实小改动比较：人是否能快速理解目标、执行者是否仍要猜接口、reviewer 是否能按验收找到证据、变更后是否容易同步。格式整齐和任务勾选都不能代替这些结果。

OpenSpec 明确说明 `status` 只看产物是否存在；`validate` 检查格式，另有 verify skill 对实现进行完整性、正确性和一致性审查。YorZ 的 lint 也不能证明业务验收通过。构建、实际行为、人工体验仍需分别提供证据。[propose 的状态说明](https://github.com/Fission-AI/OpenSpec/blob/main/skills/openspec-propose/SKILL.md)、[verify 源码](https://github.com/Fission-AI/OpenSpec/blob/main/skills/openspec-verify-change/SKILL.md)
