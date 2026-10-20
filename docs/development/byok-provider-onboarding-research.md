# BYOK 服务接入参考

文档角色：Reference。核查日期：2026-10-20（Asia/Shanghai）。

范围：阅读官方文档与公开源码，比较服务配置的交互。下文的建议是研究判断，不代表 Jotway 已决定或实现这些功能。

## 先看结论

值得借鉴的共同做法是：**先让用户选服务商，再填 API Key、选模型；协议和地址主要由预设处理。** “DeepSeek”是用户认识的服务名；“OpenAI-compatible”说明请求格式，两者不应混成一个选择。

| 项目 | 主要参考价值 | 最适合 Jotway 借鉴的一点 |
| --- | --- | --- |
| [Cherry Studio](https://github.com/CherryHQ/cherry-studio) | 服务商目录、地址预设、取 Key 链接、模型同步与检查 | 把“我用哪家服务”放在设置入口 |
| [Chatbox](https://github.com/chatboxai/chatbox) | 品牌配置、常用模型、可编辑自定义接口 | 少量常用模型先可选，仍保留手动添加 |
| [Jan](https://github.com/janhq/jan) | 本地与云端分开、云端引导、明确错误分类 | 对不同连接方式给不同表单和提示 |
| [Open WebUI](https://github.com/open-webui/open-webui) | 多连接、模型列表、共享与个人连接区分 | 明确当前使用哪条连接、谁提供 Key |

前三个是核心开源参考。Open WebUI 当前许可证有品牌保留条件，此处仅作为源码可读的补充参考，不把它与前三个的许可证等同。[Open WebUI LICENSE](https://github.com/open-webui/open-webui/blob/91ea4e3421d1d8069f13d4a463fcb5986d94ea60/LICENSE)

## Cherry Studio：参考服务商入口

1. **服务商名与接口格式分开。** 官方代码文档明确区分 `provider.id`、`endpointType`、`adapterFamily`：分别表示服务身份、接口协议、具体适配器。DeepSeek 的目录项同时保存默认接口、地址，以及 Key、账单、文档链接。Key 输入区会展示“获取 API Key”链接。[接口解析说明](https://github.com/CherryHQ/cherry-studio/blob/479af0732a9026945eb10a3bff3454ea447d3e5b/docs/references/ai/provider-resolution.md#L11-L24)、[DeepSeek 预设](https://github.com/CherryHQ/cherry-studio/blob/479af0732a9026945eb10a3bff3454ea447d3e5b/packages/provider-registry/data/providers.json#L235-L305)、[Key 输入区](https://github.com/CherryHQ/cherry-studio/blob/479af0732a9026945eb10a3bff3454ea447d3e5b/src/renderer/pages/settings/ProviderSettings/ConnectionSettings/ApiKey.tsx#L88-L100)
2. **模型同步、检查、自定义地址各有入口。** 桌面文档给出的流程是选服务商、填 Key、同步模型，再按需检查。支持 Ollama、LM Studio 等本地服务。自定义接口代码还会计算最终请求 URL，帮助识别重复路径。[配置指南](https://cherryai.com/docs/en/pre-basic/providers/)、[请求地址预览](https://github.com/CherryHQ/cherry-studio/blob/479af0732a9026945eb10a3bff3454ea447d3e5b/src/renderer/pages/settings/ProviderSettings/ProviderList/customProviderCreation.ts)

借鉴判断：Jotway 可以先有少量常见品牌预设；无需复制整个服务市场、多密钥和多协议编辑器。用户选 DeepSeek 后，应直接知道 Key 去哪拿、模型在哪选。

## Chatbox：参考少字段与模型选择

1. **品牌只是配置入口，底层可以复用协议。** DeepSeek 的定义具有独立名称，但类型是 `OpenAI`，并提供常用模型与可读名称。模型列表会合并已保存项、服务端清单、提供方 API；部分品牌还使用目录数据作为补充或回退，保留本地项优先。[DeepSeek 定义](https://github.com/chatboxai/chatbox/blob/0ac6385ae1ff5bf778777826da3c5edcd55b61b8/src/shared/providers/definitions/deepseek.ts)、[模型列表合并](https://github.com/chatboxai/chatbox/blob/0ac6385ae1ff5bf778777826da3c5edcd55b61b8/src/renderer/packages/model-setting-utils/base-config.ts)
2. **自定义配置给出地址预览；检查绑定具体模型。** 自定义服务可分别填写 API Host、API Path，并看到组合后的地址。Check 先选模型，再执行文字请求；当前源码随后还测视觉、工具能力。导入配置允许附带获取 Key、文档、模型页面链接，但这些字段可选，不能假定每个内置品牌都有。[设置实现](https://github.com/chatboxai/chatbox/blob/0ac6385ae1ff5bf778777826da3c5edcd55b61b8/src/renderer/routes/settings/provider/%24providerId.tsx)、[模型检查实现](https://github.com/chatboxai/chatbox/blob/0ac6385ae1ff5bf778777826da3c5edcd55b61b8/src/renderer/utils/model-tester.ts)、[导入配置格式](https://docs.chatboxai.app/guides/providers/import-config)

借鉴判断：先展示常用模型并保留“刷新列表”“手动输入 ID”。检查应明确针对当前服务和所选模型；Jotway 的文字功能可先只测一次短文字请求。Chatbox 的 Ollama、LM Studio 是独立入口，配置包含本机 HTTP 地址，Key 输入也按服务类型隐藏，值得作为后续本地模型体验参考。[本地服务预设](https://github.com/chatboxai/chatbox/blob/0ac6385ae1ff5bf778777826da3c5edcd55b61b8/src/shared/providers/definitions/lmstudio.ts)、[Ollama 预设](https://github.com/chatboxai/chatbox/blob/0ac6385ae1ff5bf778777826da3c5edcd55b61b8/src/shared/providers/definitions/ollama.ts)

## Jan：参考引导与错误解释

1. **本地运行与云端服务清楚分开。** 本地模型通过下载和本机引擎运行；云端模型选服务商后填 Key。内置服务配置附带 Key 获取说明、默认 Base URL、模型页面链接。自定义服务才要求选择 OpenAI / Anthropic 格式、填写地址。[快速开始](https://docs.jan.ai/desktop/quickstart)、[服务商预设](https://github.com/janhq/jan/blob/8c0615520239ba668717c20dd3a1b0733549b8f3/web-app/src/constants/providers.ts)、[自定义表单](https://github.com/janhq/jan/blob/8c0615520239ba668717c20dd3a1b0733549b8f3/web-app/src/containers/dialogs/AddProviderDialog.tsx)
2. **没有模型列表时允许手填，并说明兼容边界。** 官方指南说明 `/models` 不可用时可手填 ID；自定义模型的工具、视觉等能力不会自动判断。`Test keys` 的源码实际调用 `/models`，分别报告 401、403、429、网络错误；它没有证明所选模型能完成生成。[自定义服务指南](https://docs.jan.ai/desktop/remote-models/custom-endpoint)、[Key 检查实现](https://github.com/janhq/jan/blob/8c0615520239ba668717c20dd3a1b0733549b8f3/web-app/src/routes/settings/providers/%24providerName.tsx#L406-L476)

借鉴判断：错误提示应该告诉用户下一步，例如“Key 无效”“无权使用”“请求过多”“无法连接本机服务”。本地服务不应直接套云端表单。Jan 自定义入口仍要求非空 Key，文档建议无认证本地服务填占位值；这个绕路不适合照搬。

## Open WebUI：补充看连接边界

1. **一个连接保存地址、Key、模型范围，并可暂时关闭。** 默认通过模型接口发现；不支持发现时可指定 Model IDs。高级参数收起，普通流程先处理地址与认证。[官方连接指南](https://docs.openwebui.com/getting-started/quick-start/connect-a-provider/starting-with-openai-compatible/)、[连接表单](https://github.com/open-webui/open-webui/blob/91ea4e3421d1d8069f13d4a463fcb5986d94ea60/src/lib/components/AddConnectionModal.svelte)
2. **“连接成功”也有范围。** Direct Connections 的检查请求为 `GET /models`。标准服务端连接通过后台转发；个人直连则从浏览器请求提供方，并依赖管理员启用与 CORS。官方将个人直连标为实验功能。[检查实现](https://github.com/open-webui/open-webui/blob/91ea4e3421d1d8069f13d4a463fcb5986d94ea60/src/lib/apis/openai/index.ts#L333-L395)、[个人直连说明](https://docs.openwebui.com/features/chat-conversations/direct-connections/)

借鉴判断：Jotway 可以借鉴“显示当前连接”和“停用但保留配置”，无需引入服务器、管理员权限和浏览器直连机制。

## 可复用的交互原则

1. **品牌在前，协议在后。** 常见品牌用预设；自定义时再解释接口格式。
2. **Key 附带获取入口。** 地址自动填好，允许在高级设置中修改并查看最终请求地址。
3. **模型列表只是选择帮助。** 保留手填 ID；加载失败不清空用户原来的模型。
4. **把两种检查说清楚。** “已获取模型列表”与“所选模型已返回文字”分开；错误标明服务、模型及下一步。
5. **按实际功能适配。** 文字生成可用，不代表工具、图片、结构化输出、流式或推理参数都可用。本地服务需要另行设计地址与认证规则。

这些是本次比较形成的建议，不是上述项目统一保证的行为。对 Jotway，优先减少一次配置需要查资料、抄字段的次数，比增加服务商数量更有价值。

## 为什么少量接入代码能覆盖许多模型

需要分开看三个概念：**服务商决定请求发给谁，模型决定使用哪个能力，协议决定请求怎样组织。** 同一种协议可以服务多个品牌；同一个品牌下也能有多个模型。

例如，DeepSeek 官方提供 OpenAI 兼容请求格式和 `GET /models`，列表含模型 ID、名称等信息。应用可以维护一个 DeepSeek 预设，再加载模型供用户选择，不必为每个 ID 写一个独立实现。[DeepSeek 接入说明](https://api-docs.deepseek.com/)、[模型列表](https://api-docs.deepseek.com/api/list-models/)

Gemini 也提供 OpenAI 兼容入口及模型列表；OpenRouter 的目录还提供模态、支持参数等信息。因此，可复用的是基础请求与发现流程，具体参数、流式结束和业务输出仍需逐项确认，不能仅凭“兼容”就标记为完整支持。[Gemini 兼容说明](https://ai.google.dev/gemini-api/docs/openai)、[OpenRouter 模型目录](https://openrouter.ai/docs/guides/overview/models)

## Jotway 当前哪里不方便

以下来自当前源码，不代表对真实用户的访谈结论：

| 当前行为 | 可能给用户带来的负担 |
| --- | --- |
| 入口只有 `OpenAI-compatible` 和 `Claude (Anthropic)` | DeepSeek 用户要先判断它属于哪种接口 |
| 除 Claude 外不预填地址，模型是自由文本输入 | 用户要另查 API 地址和准确模型 ID |
| 表单没有获取 Key 链接或模型列表入口 | 第一次使用 API 的人缺少下一步指引 |
| 只保存一套个人配置 | 经常换服务的人不能简单切回另一套配置；这是否常见尚待验证 |

入口与字段见 [AISettingsView.swift](../../Sources/App/AISettingsView.swift)；协议、地址校验和适配器见 [PersonalModelConfiguration.swift](../../Sources/Plugins/PersonalModelConfiguration.swift)；单配置保存见 [ModelConfiguration.swift](../../Sources/Plugins/ModelConfiguration.swift)。

底层已经复用 OpenAI 兼容适配器，也为 DeepSeek 的特定参数保留了处理。因此，第一步可以优先研究配置引导，而不是先更换整套调用实现。这是基于源码的设计判断。

## 面向 Jotway 的交互初稿

候选流程：**选服务商 → 填 Key → 选模型 → 保存并测试。**

```text
AI 服务

服务商     [ DeepSeek                  ▾ ]
API Key    [ •••••••••••••••••••••••••• ]  获取 API Key
模型       [ 从服务商列表中选择         ▾ ]  刷新列表
           找不到模型？手动输入

           [ 保存配置 ]  [ 测试生成 ]

▸ 高级设置：API 地址、接口协议
```

这是交互示意，不是已实现界面。第一版建议只讨论以下五项：

1. **少量品牌预设。** 先考虑 DeepSeek、Kimi、OpenAI、Claude，以及“自定义兼容服务”。名单基于当前代码与本次参考，不是用户占比排行；没有验证过的组合不标记“已支持”。
2. **预填容易抄错的信息。** 选品牌后填入官方地址，提供获取 Key 链接；协议放进高级设置。切换地址不能自动把旧服务的 Key 带过去。
3. **模型以列表为主，手填为辅。** 有发现接口时读取；没有接口或加载失败时保留手填。可以提供少量维护过的常用项，但不因刷新而清空或自动替换用户已选模型。
4. **明确测试范围。** 取到模型列表只说明发现成功；短文字测试另行触发，并说明使用哪个服务、哪个模型，以及可能消耗 API 额度。不把简单回复成功描述为 Notes 归集、流式回顾等全部功能通过。
5. **先保留一个当前模型。** 多服务配置记忆、快速切换、本地模型可后续讨论，不必同时扩成模型管理中心。已有隐藏的 Jotway AI 界面和功能保留恢复能力。

有一处需要在实施前明确：当前连接测试通过 `models.text(.deep)` 请求**实际生效服务**，已有 Jotway 激活码仍优先。未来如果按钮表达“测试 DeepSeek”，就不能悄悄测试 Jotway AI。应先确定测试目标与托管优先的关系，再修改相应流程；当前研究没有改变这些规则。[当前测试入口](../../Sources/App/AISettingsView.swift)、[当前路由优先规则](../../Sources/Plugins/ModelConfiguration.swift)

本地模型也不是单纯多一个品牌：Ollama 的本地示例使用 HTTP 回环地址且不校验 API Key，而 Jotway 当前要求 HTTPS 和 Key。它需要单独设计，不应简单放宽所有远程地址与凭据限制。[Ollama 本地兼容接口](https://docs.ollama.com/api/openai-compatibility)、[Jotway 地址校验](../../Sources/Plugins/PersonalModelConfiguration.swift)

## 还需验证的用户假设

可以先用三类任务验证上述方向：已经有 DeepSeek Key 的人能否少查资料就配好；只用过聊天网页的人能否找到 Key 申请入口；使用其他服务的人能否理解“自定义”并完成配置。这些是待验证的人群划分，没有证据说明哪类占多数。

较小的验证起点是让一位已有 DeepSeek Key 的人看这份表单示意，说出自己下一步会点哪里、还有哪个字段不懂；不需要收集或展示他的 Key。

## 证据范围

本次核查了官方在线文档及以下公开分支快照：Cherry Studio `479af073`、Chatbox `0ac6385a`、Jan `8c061552`、Open WebUI `91ea4e34`。固定链接用于后续复查；分支源码不等于用户当前安装版本，在线文档也可能继续变化。

未安装或启动这些应用，未输入 Key、登录账户或发送模型请求；没有验证实际 UI、模型质量、计费、全部兼容服务，也没有审计完整凭据存储机制。

## 设置界面视觉参考

本节为 2026-10-20 的追加核查，服务于 BYOK 表单实现后的外观优化。上文“Jotway 当前哪里不方便”等内容保留为此前研究快照，不用于描述本次优化前的最新实现。本节将官方资料中观察到的布局与面向 Jotway 的建议分开记录。

### 官方资料中的布局

| 项目与证据 | 本次实际核对的布局 |
| --- | --- |
| [Cherry Studio 设置文档](https://cherryai.com/docs/en/pre-basic/settings/providers/) | 文档明确将 Get API Key 放在 API Key 字段标题旁，将 Sync models 放在 Models 标题右侧，手动添加入口紧邻同步。文档提供 Key 弹窗截图，但本次截图读取未成功，不据此判断具体色彩、圆角或像素间距。 |
| [Chatbox 设置源码：Key 区](https://github.com/chatboxai/chatbox/blob/0ac6385ae1ff5bf778777826da3c5edcd55b61b8/src/renderer/routes/settings/provider/%24providerId.tsx#L667-L715)、[模型区](https://github.com/chatboxai/chatbox/blob/0ac6385ae1ff5bf778777826da3c5edcd55b61b8/src/renderer/routes/settings/provider/%24providerId.tsx#L960-L1012) | 标签位于输入框上方；Key 输入使用可伸展宽度。字段内部采用较小间距，字段组采用较大间距。Model 标题右侧放置紧凑、轻量的 New、Reset、Fetch 操作，模型列表在下方。这里确认的是源码声明的结构与样式，未运行应用。 |
| [Jan 自定义服务弹窗源码](https://github.com/janhq/jan/blob/8c0615520239ba668717c20dd3a1b0733549b8f3/web-app/src/containers/dialogs/AddProviderDialog.tsx#L80-L179)、[官方设置指南](https://docs.jan.ai/desktop/remote-models/custom-endpoint) | 弹窗最大宽度为 460px，使用单列纵向字段；协议、地址和 Key 均有上方标签。错误就近展示，底部右侧排列取消与创建，创建使用主按钮。较窄空间仍能通过间距和操作层级区分内容。 |

### 面向 Jotway 的建议

以下为适配约 520–680pt 设置内容区、单个人配置的设计判断，不是上述项目共同保证的规范：

1. **改成上方标签、下方全宽控件。** 服务商、Key、模型沿同一左边线排列，避免原生表单把长字段挤在右侧。字段内部间距小于字段组间距，让眼睛更容易分组。
2. **辅助入口靠近对应字段。** 获取 Key 放在 Key 标签旁；加载／刷新放在模型标题旁；手动填写用次级文字入口。不要把这些操作都堆在页面底部。
3. **用轻量分隔表达层次。** 服务商与 Key 是连接信息，模型是选择，高级设置默认收起；使用原生背景、细分隔线和适量留白。Jotway 只保存一套个人配置，无需复制多服务商侧栏或模型管理中心。
4. **底部保留清楚的主次操作。** 保存作为主按钮、生成测试作为次按钮；移除 Key 采用独立且较弱的危险操作。获取模型列表的成功状态放回模型区，生成结果放在测试附近，避免两个成功提示看起来像同一种验证。
5. **减少常驻说明的长度，保留决定所需的信息。** 普通提示使用较弱文字层级；错误保持可读。请求发往哪里、当前实际生效服务以及测试可能消耗额度仍明确展示。不要用绿色“已配置”样式暗示尚未完成的实网生成验证。

核查局限：本次通过 Ego Browser 读取 Cherry Studio 官方公开设置页面，并读取 Chatbox、Jan 的上述公开源码及 Jan 官方说明。Ego 的页面截图命令两次超时，Jan 图片经另一只读工具读取也超时，因此没有完成截图视觉核验；没有安装、登录或运行这些参考应用，也没有验证其真实操作状态、主题或响应式效果。源码链接固定于此前研究快照，在线文档可能继续变化。
