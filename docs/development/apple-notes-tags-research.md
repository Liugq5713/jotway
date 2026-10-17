# Apple Notes 原生标签与自动化

> Role: **Reference**
> 查阅日期：2026-10-09。记录公开资料和集成建议，不代表 Jotway 已实现这些行为。

## 结论

社区已有直接对应的解决方式：将标签名称作为独立数据传给 Shortcuts，先调用 **Create Tag**，再把产生的标签对象传给 **Add Tags to Notes**。向备忘录正文写入 `#工作`，与为该备忘录添加可点击、可筛选的原生标签，是两种不同操作。Drafts 社区讨论和开源 `apple-notes-mcp` 的工作流代码都采用或建议这条路径。[Drafts 讨论](https://forums.getdrafts.com/t/exporting-to-apple-notes-preserving-tags/11612)、[工作流生成源码](https://github.com/sweetrb/apple-notes-mcp/blob/main/scripts/build-native-tags-shortcut.py)

## 证据与边界

| 来源 | 能确认什么 | 不能据此确认什么 |
| --- | --- | --- |
| [Apple：Mac 上使用标签](https://support.apple.com/en-tj/guide/notes/apdc88ed7f1d/mac) | 在 Notes 编辑器输入或选择标签后，标签进入侧栏；原生标签也可以转换回普通文字。 | 没有承诺导入 HTML 或设置 AppleScript `body` 会激活标签。 |
| [Drafts 社区，2021-11 与 2025-08](https://forums.getdrafts.com/t/exporting-to-apple-notes-preserving-tags/11612) | Drafts 作者的实际测试发现，粘贴、Shortcuts 设置正文和 AppleScript 设置正文留下普通 `#hashtag` 文本；2025 年用户报告 macOS 15.5 仍有相同行为，后续回复建议使用专用标签 actions。 | 历史用户报告不能代替每个当前 macOS 版本的端到端测试。 |
| [MPU 社区，2023-05](https://talk.macpowerusers.com/t/how-do-you-add-tag-to-apple-notes-with-shortcuts/33770) | 用户尝试后确认可行；讨论明确区分 Create Tag 创建标签与 Add Tags to Notes 将标签关联到备忘录。 | 单独 Create Tag 不等于已经给目标备忘录加标签。 |
| [apple-notes-mcp 源码](https://github.com/sweetrb/apple-notes-mcp/blob/main/scripts/build-native-tags-shortcut.py) | macOS 工作流逐个调用 `com.apple.Notes.CreateTagLinkAction` 和 `com.apple.Notes.AddTagsToNotesLinkAction`；标签输出直接接到添加动作，目标必须唯一。 | 开源实现存在不代表 Jotway 已接入或已通过本机验收。 |

Apple 的 [Shortcuts 更新说明](https://support.apple.com/en-qa/101583) 明确列出了这两个标签 actions，但所在小节标题是 iOS/iPadOS 16.0、watchOS 9.0，不能仅凭该页推断 macOS 的最低支持版本。macOS 路径另有上述开源实现和 Drafts 社区的 CLI 集成讨论作为证据；产品仍应在支持的系统版本检查动作是否可用。

## 社区实现值得借鉴的部分

`apple-notes-mcp` 明确区分正文中的 `hashtags` 与原生标签：`create-note` 的 `tags` 参数只是返回数据，内联 `#hashtag` 是可搜索的文字，真正写入标签由 `add-native-tags` 完成。它通过 Shortcuts 写入，通过读取原生数据验证结果；原生数据读取需要完整磁盘访问权限。该项目没有把正文正则匹配当作原生标签成功的证据。[项目 README](https://github.com/sweetrb/apple-notes-mcp#readme)

该项目打包签名 Shortcut，并要求用户确认添加；首次运行还可能需要 Notes 授权。它特别记录了后台运行等待首次权限提示而超时的情况，因此安装存在不等于运行就绪。它使用“标题＋已有的独特正文片段”筛选目标，遇到零个或多个匹配就停止；服务端读取结果并检查内容保留情况。[桥接说明](https://github.com/sweetrb/apple-notes-mcp/blob/main/shortcuts/README.md)

Apple 官方支持通过 `shortcuts run` 从命令行调用已安装的 Shortcut，使用 `-i` 传输入文件、`-o` 写输出文件；如果工作流请求用户输入，命令会等待。因此可以将这条路径集成到原生应用，但不能承诺首次使用完全无提示。[Apple CLI 文档](https://support.apple.com/en-gb/guide/shortcuts-mac/apd455c82f02/mac)

## 对 Jotway 的集成建议

以下是基于资料的设计建议，不是已完成的修复。

1. 保留 AI 输出的独立标签数组。正文与标签分别交给存入流程，不把拼接 `#标签` 当作原生标签写入。
2. 为保留当前正文格式，优先评估“现有 Apple Events 创建 → Shortcut 添加原生标签”，但必须解决创建返回的备忘录 ID 与 Shortcut 目标对象之间的可靠匹配，不能只按标题取第一个结果。另一方案是在同一个 Shortcut 内创建并添加标签，直接使用创建动作返回的备忘录对象；这减少重新查找，却需要重新验证目标账户、文件夹和正文格式是否满足 Jotway 当前行为。
3. 分开表达“正文已存入”和“标签已添加”。标签动作失败时保留已创建备忘录的标识，后续只补标签，避免重试整个 action 产生重复备忘录。不要在写入原生标签后再次用整段 HTML 覆盖正文；社区项目也对含原生对象的正文替换作了保护。[项目 README](https://github.com/sweetrb/apple-notes-mcp#readme)
4. 验收以 Notes 标签侧栏或按原生标签筛选能找到新备忘录为准；正文能搜到 `#标签` 不足以证明成功。UI 自动输入可以尝试触发编辑器转换，但会引入窗口、焦点和输入时序依赖，不适合作为 Jotway 默认存入路径。直接写 Notes 私有数据库也不建议；可参考项目的 Shortcuts 写入、数据库只读分工，而不是承担私有存储写入的兼容性成本。[项目说明](https://github.com/sweetrb/apple-notes-mcp#readme)

本次只查阅文档、社区原始讨论和开源代码，没有启动或操作 Notes、Shortcuts 或 Jotway，也没有在本机创建测试备忘录。上述推荐仍需最小端到端验证。
