# Codex 后台任务与桌面侧栏

> Role: **Reference**
> 调研日期：2026-10-10
> 范围：Jotway `@codex` 创建的本地会话；不等同于 ChatGPT 云端聊天同步。

**方案判断：官方 `codex app-server` 创建新任务可以消除 `exec` 来源过滤的影响，同时应保留直达会话与结果文件入口。** 官方源码提供了可行依据：当前 CLI 启动的 app-server 使用 `VSCode` 会话来源，属于默认历史列表收录的交互式来源。但默认列表查询成功仍不等于桌面端实际刷新与显示已验收。Jotway 的具体接入行为见 [Codex action](../integrations/codex.md)。旧 `exec` 会话可以考虑 fork 成新会话；这会产生新 ID。[CLI 启动源码](https://github.com/openai/codex/blob/rust-v0.162.1/codex-rs/cli/src/main.rs#L1282-L1291)、[官方列表规则](https://learn.chatgpt.com/docs/app-server#list-threads-with-pagination--filters)

## 方案比较

| 方案 | 能解决什么 | 限制与判断 |
| --- | --- | --- |
| 会话深链接、结果文件和任务文件夹 | 完成提示消失后仍能找回任务。当前工作区已实现这一入口，见 [Codex action](../integrations/codex.md)。 | 不改变会话来源，不保证侧栏永久显示。社区报告：原 `exec` 会话在桌面端继续了多轮对话，离开后仍从列表消失。[#42083](https://github.com/openai/codex/issues/42083) |
| 官方 app-server 创建新任务 | 用 `initialize` → `thread/start` → `turn/start` 执行，并保存线程 ID；当前 CLI 的新线程默认来源有条件进入交互式列表。 | **推荐验证的产品方案。** 需要实现双向 RPC、事件处理、错误与取消，并保留现有权限约束和结果落盘；还要检查桌面端是否使用相同本地存储、项目/路径筛选、重启后的列举结果。[官方协议](https://learn.chatgpt.com/docs/app-server)、[来源源码](https://github.com/openai/codex/blob/rust-v0.162.1/codex-rs/cli/src/main.rs#L1282-L1291) |
| 直接修改 Codex 私有数据库的 `source` | 社区有人报告将 `exec` 改为 `vscode` 后能够列出。 | 仅是社区临时排查手段，**不建议产品化**：它绕过公开接口，不能保证日志、索引和后续版本一致。此次没有修改数据库。[#45791 评论](https://github.com/openai/codex/issues/45791#issuecomment-5688548681) |

## 官方事实：为什么会隐藏

`thread/list` 的 `sourceKinds` 省略或设为 `[]`，都只列交互式来源 `cli`、`vscode`；显式传入 `exec` 才能将这类后台会话纳入查询。列表还可以按 `cwd`、归档状态等条件筛选。因此，“磁盘上有会话”“按 ID 可以读”“侧栏能够列出”是不同事实。[官方文档](https://learn.chatgpt.com/docs/app-server#list-threads-with-pagination--filters)、[过滤器实现](https://github.com/openai/codex/blob/c3d3b142d10f4316b46e35aad7e5317e7e506cb7/codex-rs/app-server/src/filters.rs#L6-L15)

OpenAI 维护者在 #16385 明确说明，`exec` 和 `codex_mcp` 与 TUI、IDE、桌面端创建的交互式会话分开标记是有意设计；该 issue 以 `not_planned` 关闭。后续社区仍在请求桌面端提供“显示所有会话”能力，这不是 Jotway 自己打开一个配置就能保证解决的问题。[维护者回复](https://github.com/openai/codex/issues/16385#issuecomment-4166889629)、[#27366](https://github.com/openai/codex/issues/27366)

## app-server 的来源选择

1. **协议名称不等于持久化来源。** 当前 `codex app-server` 的 CLI 分支把 `SessionSource::VSCode` 传给服务；独立 `codex-app-server` 可用 `--session-source` 选择来源，默认也是 `vscode`。不能根据 API 中存在 `appServer` 枚举，就断言这种接入一定会创建 `appServer` 来源。[CLI 0.162.1](https://github.com/openai/codex/blob/rust-v0.162.1/codex-rs/cli/src/main.rs#L1282-L1291)、[独立服务参数](https://github.com/openai/codex/blob/c3d3b142d10f4316b46e35aad7e5317e7e506cb7/codex-rs/app-server/src/main.rs#L51-L59)

2. **`clientInfo.name` 不负责将线程改成 `vscode`。** 初始化代码用它记录客户端身份、originator 和 user-agent；session source 在服务启动时另行传入。因此 Jotway 应使用自己的真实客户端名称，无须伪装成桌面端或 VS Code。[初始化实现](https://github.com/openai/codex/blob/rust-v0.162.1/codex-rs/app-server/src/request_processors/initialize_processor.rs#L94-L168)、[官方客户端说明](https://github.com/openai/codex/blob/rust-v0.162.1/codex-rs/app-server-client/README.md#startup-identity)

3. **`threadSource` 是另一字段。** 本机生成的 `ThreadStartParams` 和 `ThreadForkParams` 将它说明为客户端提供的 analytics source classification；设置它不等于改变 `sourceKinds` 过滤使用的 session source。[协议定义](https://github.com/openai/codex/blob/c3d3b142d10f4316b46e35aad7e5317e7e506cb7/codex-rs/app-server-protocol/schema/typescript/v2/ThreadStartParams.ts)

4. **新建可行依据充分，但桌面可见性仍需实测。** 服务返回的线程元数据来源可验证；同一个线程能否出现在目标侧栏，还受桌面端筛选、存储位置和刷新行为影响。独立 app-server 的事件也不等于桌面端已经加载该线程。这是依据协议与桌面筛选机制作出的推断，并非本次实际 UI 验收结果。

## 旧任务：resume 与 fork 的区别

`thread/resume` 恢复同一 ID，并从已存历史读取原 session source；因此恢复 `exec` 不应被视为自动转为交互式来源。官方文档也说明，resume 本身不更新线程修改时间。[恢复源码](https://github.com/openai/codex/blob/c3d3b142d10f4316b46e35aad7e5317e7e506cb7/codex-rs/core/src/thread_manager.rs#L1302-L1312)、[官方恢复说明](https://learn.chatgpt.com/docs/app-server#start-or-resume-a-thread)

`thread/fork` 复制历史并创建新 ID。当前源码中，fork 历史不使用 resumed session source，未显式设置时会取当前服务的默认来源；普通 app-server 默认 `VSCode`，因此**fork 成交互式副本是有源码依据的旧任务迁移候选**。它没有修改原线程，也不能让原有通知链接自动指向新 ID。[fork 过程](https://github.com/openai/codex/blob/c3d3b142d10f4316b46e35aad7e5317e7e506cb7/codex-rs/core/src/thread_manager.rs#L1584-L1636)、[fork 与 resume 的元数据区分](https://github.com/openai/codex/blob/c3d3b142d10f4316b46e35aad7e5317e7e506cb7/codex-rs/history/src/lib.rs#L523-L530)、[默认来源](https://github.com/openai/codex/blob/c3d3b142d10f4316b46e35aad7e5317e7e506cb7/codex-rs/core/src/thread_manager.rs#L2103-L2105)

实施前需确认历史格式与目标版本兼容，保留新旧 ID 的对应关系，并先在一个已完成任务上验证：历史完整、可继续对话、切换会话后能列出、桌面端重启后仍能列出。此处的 fork 判断只依据文档、源码和本机协议，尚未通过旧任务迁移实测。

在已核对的公开方法、协议 schema 与源码路径中，**未发现可在保留原线程 ID 的同时把 `exec` 提升为交互式来源的公开 promotion/adoption 参数**。这是本次检索范围内的结论，不宣称所有未来版本或内部接口都不存在这种能力。[线程方法](https://learn.chatgpt.com/docs/app-server#threads)、[当前线程协议](https://github.com/openai/codex/blob/c3d3b142d10f4316b46e35aad7e5317e7e506cb7/codex-rs/app-server-protocol/src/protocol/v2/thread.rs)

## 置顶、分组与文档版本差异

在线官方文档列出了 `thread/metadata/update` 的 `isPinned` 以及 `thread/list` 的 `isPinned` 过滤。但本机 `codex-cli 0.162.1` 生成的 experimental TypeScript schema 中，这两个字段均不存在；`ThreadMetadataUpdateParams` 只有线程 ID、projectId、gitInfo 和 daybreakEnabled，分组由 `thread/section/move` 表达。公开源码也与这个本机 schema 一致。**不能仅复制在线文档里的 pin 示例，便宣称本机已支持或能绕过来源过滤。**[在线元数据文档](https://learn.chatgpt.com/docs/app-server#update-stored-thread-metadata)、[当前协议源码](https://github.com/openai/codex/blob/c3d3b142d10f4316b46e35aad7e5317e7e506cb7/codex-rs/app-server-protocol/src/protocol/v2/thread.rs)

#45791 的 Windows 用户报告，移动到自定义分组成功、成员关系也已持久化，但来源为 `exec` 的线程仍未被桌面列表返回。因此“置顶或分组”需单独验证，不能当成已证明的通用解决方案。[社区补充](https://github.com/openai/codex/issues/45791#issuecomment-5774732432)

## 本机证据与研究边界

- CLI：`command codex --version` 返回 `codex-cli 0.162.1`。使用 `command` 避开本机交互 shell 中额外 CLI 参数的 alias。
- 协议：运行 `command codex app-server generate-ts --experimental --out /private/tmp/jotway-codex-sidebar-types-20261010`；检查 `ThreadStartParams`、`ThreadResumeParams`、`ThreadForkParams`、`ThreadListParams`、`ThreadMetadataUpdateParams` 和 `ThreadSectionMoveParams`。这些临时文件用于确认本机可用字段，不作为产品文件。
- 桌面：当前安装 `/Applications/ChatGPT.app`，版本 `26.1007.21159`，build `20052`。只读检查 bundled `app.asar` 的 generic list 路径：默认 `sourceKinds` 最终解析为 `[]`，发送 `thread/list` 时同时使用 `useStateDbOnly: true`。这与官方交互式默认过滤一致；没有把源码检查描述为实际侧栏验收。
- 社区报告分别来自 2026 年 4 月、6 月和 9 月，涉及不同版本；#42083、#45791 的复现细节可解释现象，不能保证所有桌面版本行为完全相同。本机源码核对缩小了这种不确定性。
- 本页记录来源过滤与方案依据，不作为实际桌面侧栏验收报告；当前实现以 [Codex action](../integrations/codex.md) 为准。没有通过改写 Codex 私有存储或批量迁移旧会话来绕过过滤。
