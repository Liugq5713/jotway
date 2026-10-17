# Apple Notes 正文格式与可读性

> Role: **Reference**
> 查阅日期：2026-10-09。记录公开格式能力与集成边界，不代表 Jotway 已实现或已通过 Notes 实机验收。

## Notes 支持哪些格式

| 能力 | Apple 官方确认的范围 |
| --- | --- |
| 标题、正文、强调 | Notes 编辑器支持 Title、Heading、Subheading、Body，以及粗体、斜体、下划线、删除线、字体与高亮。段落样式要求使用 iCloud 或“在我的 Mac 上”的备忘录。[macOS 15 格式指南](https://support.apple.com/en-au/guide/notes/apd1955d3b21/4.11/mac/15.0) |
| 列表 | 支持项目符号、短横线、编号、缩进；勾选清单要求使用 iCloud 或本机账户。[macOS 26 列表指南](https://support.apple.com/guide/notes/add-lists-apd93c815aa0/4.13/mac/26) |
| 链接 | 编辑器支持网页链接、备忘录之间的链接，以及部分 App 内容链接。[macOS 26 链接指南](https://support.apple.com/guide/notes/add-links-apde615d29c2/4.13/mac/26) |
| 等宽、引用、表格 | macOS 26 的官方快捷键表列出 Monostyled、Block Quote 和插入表格。[macOS 26 快捷键](https://support.apple.com/guide/notes/keyboard-shortcuts-and-gestures-apd46c25187e/4.13/mac/26) |
| 折叠与 Markdown | macOS 15 的 Heading / Subheading 可折叠下方内容；Markdown 文件导入从 macOS 26 开始提供，会转换为富文本。两者分别是编辑器能力与文件导入流程。[折叠章节](https://support.apple.com/en-au/guide/notes/apd1955d3b21/4.11/mac/15.0)、[文件导入](https://support.apple.com/en-us/102223) |

## HTML 写入的边界

本机 Notes 4.13 的 AppleScript 字典将 `note.body` 定义为可写的 HTML 内容，`plaintext` 为只读纯文本；字典没有列出支持的 HTML 标签、CSS 属性、原生段落样式映射或折叠状态接口。[本机 Notes.sdef，第 110–143 行](/System/Applications/Notes.app/Contents/Resources/Notes.sdef:110)、[Notes 版本元数据](/System/Applications/Notes.app/Contents/Info.plist)

因此，“Notes 编辑器支持某格式”不能直接作为“写入 `<h2>`、`<blockquote>`、`<pre>` 或 CSS 后就保留同样原生行为”的证据；也不能用 Markdown 文件导入能力推断 `body` 会解析 Markdown。上述官方资料没有为这些映射提供承诺，具体效果仍需在目标系统和账户上验证。[Notes.sdef](/System/Applications/Notes.app/Contents/Resources/Notes.sdef:125)、[文件导入](https://support.apple.com/en-us/102223)

`<pre>` 在 HTML 标准中表达预格式化文本，适合代码或需要保留文字排布的片段；它不是“AI 内容”的语义容器。HTML 标准说明的是 HTML 语义，并不证明 Notes 的导入行为。[WHATWG：pre](https://html.spec.whatwg.org/multipage/grouping-content.html#the-pre-element)

## 对 Jotway 的保守建议

以下为设计建议，而非支持保证：

1. 以明确的章节名区分“我的记录”“相关记录 · AI 整理”“AI 补充”；用短段落、粗体标签、简单列表建立层级。原文保持原有文字与顺序。
2. 每条历史关联只展示一句有信息量的摘要，再附一行来源标题、日期和短链接。把相同的查找入口提示移到整个历史区末尾；只有话题标签、没有具体内容的候选不应占据正文。
3. 采用简单 HTML：`div` / `p`、`br`、`b` / `strong`、`ul` / `ol` / `li`、`a`；这些是建议验证的最小集合，不是 Apple 发布的支持白名单。格式被简化后，正文也应凭章节名和文本顺序保持可读。
4. AI 分区优先使用普通正文和独立标题。将 `<pre>` 留给真正需要保留排布的内容；避免把整段中文分析变成预格式文本。避免把固定颜色、背景、边框或 CSS 间距当作唯一分区手段。
5. 不以 `<h2>` 写入成功宣称获得原生折叠章节，也不以浏览器预览宣称完成 Notes 验收。若增加原生折叠能力，需单独验证 Heading / Subheading 在目标 Notes 版本中的实际映射。

## 点击来源直接打开原备忘录

Apple 官方介绍的原生备忘录互链是在 Notes 编辑器使用“添加链接”或输入 `>>`，再选择目标备忘录；该页面没有公开“AppleScript note ID 转换为链接”的算法。[macOS 26 链接指南](https://support.apple.com/guide/notes/add-links-apde615d29c2/4.13/mac/26)

本机 Notes 的 `Info.plist` 注册了 `notes` 与 `applenotes` 两个 URL scheme；这证明应用声明处理这些协议，却不能证明 `notes://<note ID>` 或 `applenotes:<note ID>` 是正确的定位格式。字典的 `note` 没有 URL 属性，`open note location` 只描述接收 URL；`show` 明确支持 note 对象。[Notes Info.plist](/System/Applications/Notes.app/Contents/Info.plist)、[Notes.sdef，第 10–32 行](/System/Applications/Notes.app/Contents/Resources/Notes.sdef:10)、[note 属性](/System/Applications/Notes.app/Contents/Resources/Notes.sdef:110)

建议在来源标题上使用 Jotway 自己定义的链接，例如 `jotway://notes/open?id=<编码后的真实来源 ID>`：由 Jotway 解析并校验 URL，再按该 ID 调用 Notes 的公开 `show` 命令。AppKit 官方支持在 `CFBundleURLTypes` 注册自定义 scheme，并由 `application(_:open:)` 接收打开请求；Notes 字典提供了展示 note 对象的操作，因此这条方案不需要猜测 Notes 私有 URL 格式。[AppKit URL 入口](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/application(_:open:))、[CFBundleURLTypes](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleurltypes)、[Notes show](/System/Applications/Notes.app/Contents/Resources/Notes.sdef:18)

这是应用桥接链接的设计建议，不是 Apple 原生备忘录互链：应标明需要安装 Jotway 的这台 Mac，并处理原备忘录不存在或授权不可用的结果。是否保留 HTML 中的自定义 scheme 链接、点击是否抵达正确备忘录，都需要实际验收。共享链接是另一套权限流程，不宜为实现本机来源跳转而自动创建共享。[Apple 共享链接说明](https://support.apple.com/guide/notes/manage-shared-notes-and-folders-apd881ec5518/mac)

本次仅阅读 Apple 官方文档、HTML 标准、应用自带字典及 Jotway 相关源码；未启动或操作 Notes / Jotway，未读取用户备忘录正文，未创建测试备忘录或共享链接。HTML 的具体渲染、暗色模式、折叠状态、来源点击及跨设备效果均未做实机验证。
