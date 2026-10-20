# 移除 Notes AI 补充：交付记录

本项停止普通保存、归集追加、启动及配置变化中的补充请求、五分钟等待和刷新写入。标题与当天恢复、原文 FIFO、安全读回、分类和只读回顾保留。旧生成文字、已有覆盖说明及可验证来源链接保留；不新增过时提示，不清理用户数据。旧 `pending.refresh` 仅解码及读取核对，不生产或重放。

## 自动检查

- `swift build`：退出 0。VFS 仅将 `StorageLocation.userHome` 指向本项空目录，`swift build --build-tests -Xswiftc -vfsoverlay -Xswiftc <test-vfs.json>`：退出 0。
- 直接 `sandbox-exec ... xctest -XCTest JotwayTests.LauncherActionTests,JotwayTests.AIProviderTests`：10/10，退出 0；最终源变更后再次通过。策略拒绝真实 Jotway／旧容器数据、Notes、Keychains/securityd 和网络，合成读／写／网络拒绝自检通过。
- 临时命令行调用实际编译模块：31/31，退出 0。覆盖旧尾部与元数据、可验证链接、纯文字降级、只有覆盖说明的旧记录、标题非标题区保持、回顾原文提取、旧 refresh 解码／匹配与未匹配保护、旧偏好 round trip 与版本、回顾解析。首轮发现旧空 div 被通用读取器双计空行，已局部修复并保留失败证据。
- 静态调用链 21 项通过：无补充生产器／刷新生产／旧偏好消费；协调器对账无外部写入，未解决记录继续保护候选与标题。旧数据恢复检查用合成存储，未调用真实 Notes。
- 从 HEAD 加本项独立增量的候选 index 导出 134 个 Swift blob，整模块 `swiftc -typecheck` 退出 0。工作树含未交付 Instant Insight；候选编译独立证明本项不依赖它。
- 四份规格同步完成；`openspec validate remove-notes-ai-insights --strict` 与 `openspec validate --specs --strict` 退出 0，后者 23/23。严格校验针对当前工作树；仍未提交的旧格式修复保持隔离。

证据位于 Git common dir 的 `codex-openspec-queue/runs/02671d31-36c5-40cc-8571-befc03186215/remove-coder/`，包含完整命令、退出码、隔离策略、源码与 blob 清单、日志、增量及剩余外部 patch。

## 隔离与限制

删除两个只测试退休补充器的既有用例，原有渲染用例改查原文和旧标签，不新增仓库测试。Instant Insight 保持用户决定的 8/10 blocked，所有代码／规划差异排除本提交；独立 selected-text 规划、AGENTS／CONTEXT 术语也排除。三份仍适用的用户批准格式修复保持未提交；第四份属于本项完整退休的 `notes-ai-assistance` 写作偏好需求，随该需求删除自然消失。

此前 panel 测试曾走到默认真实凭据读取路径，真实读取／权限影响未知，未进一步访问或清理；其归档说明已通过独立 `9a6df99` 纠正。本项使用审计过的 VFS 与进程沙箱。迁移父提交 `46f870a` 来自用户授权的另一聊天，不属于本项功能提交；用户允许随当前分支普通推送。

## 人工验收清单

人工验收未执行；用户已取消其强制门槛，非阻塞。构建、合成存储与 AppKit 文本转换不证明真实 Notes 显示、权限、模型质量或窗口行为。

- 普通保存：完整原文与标题一次出现，无洞察或补充等待，确认后仅一次保存通知。
- 归集追加：当天正确主题、全部原文与时间线保留；含旧洞察和覆盖说明的笔记保持全部旧内容与来源链接，不生成新提示；手动编辑冲突时保留旧笔记。
- 标题恢复：仅当天合法任务补标题，所有非标题区域不变，无第二次保存通知。
- 回顾与草稿思考提示：保留独立入口及既有行为，结果不写回 Notes；本项不验收尚未交付的 Instant Insight 路由。
- Notes 浅色／深色真实显示及窗口、IME、VoiceOver：未执行。
