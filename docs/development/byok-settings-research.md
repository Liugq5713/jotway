# BYOK 模型服务接入方式参考

角色：Reference。查阅日期：2026-10-18。

范围：Cherry Studio、Chatbox、TypingMind 的官方文档。下述流程由文档证实，未安装或操作这些产品，未提交 API 密钥或发送真实模型请求；界面位置可能随版本调整。本文不定义 Jotway 当前行为或待实施方案。

## 官方资料证实的接入流程

| 产品 | 常规接入 | 地址与自定义 | 模型与验证 |
| --- | --- | --- | --- |
| Cherry Studio | 设置 → 模型服务 → 对应服务商；内置服务商通常只需填 API 密钥。 | 内置地址通常保持默认；自定义服务商填写名称、密钥和端点，更多设置支持从预设创建。 | 获取模型列表后按需添加，也可手填模型 ID；检测时选择模型；还需打开服务商启用开关。 |
| Chatbox | 设置 → Model Provider → 选择服务商；DeepSeek 官方示例只要求粘贴密钥并点击 Check。 | 自定义入口添加名称、API 类型、Key、Host；文档提供默认请求路径，特殊服务按其说明修改。 | 自定义服务至少添加一个模型，可配置模型能力；保存后检查连接；使用时从模型选择器选模型。 |
| TypingMind | Models → API Keys，或点击服务商旁的齿轮配置密钥。 | 内置服务商与 Add Custom Models 分开；后者承接列表外模型。 | OpenRouter 示例是填 Key 后回 Models 启用所需模型；模型管理支持搜索、服务商筛选、能力说明、默认模型与可见性设置。 |

上表来源：Cherry Studio [模型服务设置](https://docs.cherryai.com.cn/pre-basic/providers/providers)、[自定义服务商](https://docs.cherryai.com.cn/pre-basic/providers/zi-ding-yi-fu-wu-shang)；Chatbox [模型配置](https://docs.chatboxai.app/en/guides/providers)、[DeepSeek 设置](https://beta.chatboxai.app/en/guide/byok/deepseek)（后者位于官方 beta 站点）；TypingMind [API Keys Setup](https://docs.typingmind.com/manage-and-connect-ai-models/set-up-api-keys)、[OpenRouter](https://docs.typingmind.com/manage-and-connect-ai-models/openrouter)、[Manage Models](https://docs.typingmind.com/manage-and-connect-ai-models/manage-ai-models)。

## 有用的差异

- **连接成功与进入可选列表是两个步骤。** Cherry Studio 文档明确要求添加模型及启用服务商；TypingMind 的 OpenRouter 指南也要求另行启用模型。因此，填好 Key 不一定意味着用户已能选到模型。[Cherry Studio](https://docs.cherryai.com.cn/pre-basic/providers/providers)、[TypingMind](https://docs.typingmind.com/manage-and-connect-ai-models/openrouter)
- **获取密钥的帮助可以按服务商提供。** Chatbox 的 DeepSeek 指南直接链接密钥平台，并分别解释鉴权、余额、模型不可用问题；TypingMind 的 OpenRouter 指南给出账户、创建密钥、接入步骤。这里证实的是文档引导，不代表所有设置界面均内置相同按钮。[Chatbox](https://beta.chatboxai.app/en/guide/byok/deepseek)、[TypingMind](https://docs.typingmind.com/manage-and-connect-ai-models/openrouter)
- **“验证”的具体行为不能一概而论。** Cherry Studio 明确让用户选模型检测；Chatbox 明确有 Check。此次读取的 TypingMind 通用设置及 OpenRouter 指南没有交代统一验证按钮或测试请求，故不把自动验证列为已证实功能。[Cherry Studio](https://docs.cherryai.com.cn/pre-basic/providers/providers)、[Chatbox](https://docs.chatboxai.app/en/guides/providers)、[TypingMind](https://docs.typingmind.com/manage-and-connect-ai-models/set-up-api-keys)

## 跨产品观察（归纳，非官方结论）

三款都给常见服务商提供具名入口，并把自定义接入作为另一条路径；服务商认证与模型选择也具有不同职责。其可复用的设计思路是：先让用户认出自己购买服务的平台，再填写密钥、选择模型；协议、端点等细节主要服务于自定义接入。上述样本不足以证明这是全部 BYOK 产品的统一惯例，也不能据此推断接入成功率。

## 原生实现源码核查：macai

本节与前面的产品文档调研不同：读取了 Renset/macai 的固定源码快照与许可证，未安装、构建或运行该产品，未发送模型请求。核查版本为 [`99300f753172e82bae0d70919c16897b2fea9a5b`](https://github.com/Renset/macai/commit/99300f753172e82bae0d70919c16897b2fea9a5b)，GitHub 提交时间为 2026-08-16。以下是代码行为和复用判断，不是实机体验结论。

**判断：对 SwiftUI 原生应用，macai 是值得优先参考的实现样本。** 它有简化向导和高级表单两条路径，源码采用 [Apache-2.0](https://github.com/Renset/macai/blob/99300f753172e82bae0d70919c16897b2fea9a5b/LICENSE.md)。复制或修改其代码并分发时，须保留适用版权与归属声明、随附许可证、标明修改；若所用分发包含 NOTICE，还需保留适用 NOTICE。以下建议不表示把整套聊天客户端移入 Jotway。

| 可参考部分 | 固定版本入口 | 已核实行为与边界 |
| --- | --- | --- |
| 简化接入向导 | [APIServiceTemplateAddView](https://github.com/Renset/macai/blob/99300f753172e82bae0d70919c16897b2fea9a5b/macai/UI/Preferences/TabAPIServices/APIServiceTemplateAddView.swift)、[对应 ViewModel](https://github.com/Renset/macai/blob/99300f753172e82bae0d70919c16897b2fea9a5b/macai/UI/Preferences/TabAPIServices/APIServiceTemplateAddViewModel.swift) | 选预设 → 配置 → 测试；填 Key 旁有获取指引。先持久化配置再测试，成功后才允许 Start using；故不能描述成“验证成功才保存”。 |
| 服务商预设 | [APIServiceTemplates.json](https://github.com/Renset/macai/blob/99300f753172e82bae0d70919c16897b2fea9a5b/macai/Configuration/APIServiceTemplates.json)、[AppConstants.swift](https://github.com/Renset/macai/blob/99300f753172e82bae0d70919c16897b2fea9a5b/macai/Configuration/AppConstants.swift#L166) | 预设展示名称、默认模型和能力；配置包含默认地址、Key 获取链接、模型说明链接、后备模型。适合借数据结构；具体型号与地址仍须重新核对。 |
| 高级表单 | [APIServiceDetailView](https://github.com/Renset/macai/blob/99300f753172e82bae0d70919c16897b2fea9a5b/macai/UI/Preferences/TabAPIServices/APIServiceDetailView.swift#L69) | 地址可恢复默认，模型下拉可转手填，提供刷新模型与独立测试按钮。Key 输入是失焦模糊的 TextField，不能等同于系统 SecureField。 |
| 获取模型 | [DetailViewModel](https://github.com/Renset/macai/blob/99300f753172e82bae0d70919c16897b2fea9a5b/macai/UI/Preferences/TabAPIServices/APIServiceDetailViewModel.swift#L132)、[ChatGPTHandler](https://github.com/Renset/macai/blob/99300f753172e82bae0d70919c16897b2fea9a5b/macai/Utilities/APIHandlers/ChatGPTHandler.swift#L139) | 调用服务商适配器的 fetchModels；空列表或失败时使用预设模型，手填仍可用。ChatGPT 适配器从完整聊天端点推导 models 地址，不可直接套到任意 Base URL 约定。 |
| 真实连接测试 | [ButtonTestApiTokenAndModel](https://github.com/Renset/macai/blob/99300f753172e82bae0d70919c16897b2fea9a5b/macai/UI/Preferences/TabAPIServices/ButtonTestApiTokenAndModel.swift#L33)、[MessageManager.testAPI](https://github.com/Renset/macai/blob/99300f753172e82bae0d70919c16897b2fea9a5b/macai/Utilities/MessageManager.swift#L268) | 使用表单的服务商、地址、Key、模型创建适配器，发送测试消息；成功/失败状态与错误说明来自该生成请求，不仅是模型列表接口。 |
| 密钥持久化 | [TokenManager](https://github.com/Renset/macai/blob/99300f753172e82bae0d70919c16897b2fea9a5b/macai/Utilities/TokenManager.swift) | 使用 KeychainAccess；同时包含本地/iCloud 两种路径。该部分与 macai 同步偏好耦合，应结合 Jotway 现有密钥存储取舍。 |

**复用时需要改进的地方（源码观察后的工程判断）：** 高级表单的取模型函数对用户输入地址使用 `URL(string:)!`；每次 Key 改动直接触发取模型任务，函数内未实现请求取消或旧结果隔离；测试按钮内部成功状态没有针对配置修改的失效处理。因此适合借界面结构、预设结构和测试请求边界，不宜原样复制整个 ViewModel。相关代码见 [模型获取与 Key 变更](https://github.com/Renset/macai/blob/99300f753172e82bae0d70919c16897b2fea9a5b/macai/UI/Preferences/TabAPIServices/APIServiceDetailViewModel.swift)、[测试按钮状态](https://github.com/Renset/macai/blob/99300f753172e82bae0d70919c16897b2fea9a5b/macai/UI/Preferences/TabAPIServices/ButtonTestApiTokenAndModel.swift)。

## 扩展机制参考：Big-AGI

主线源码核查固定于 [`06b0dec07e0134c26dff17951390b5509a8ba0aa`](https://github.com/enricoros/big-AGI/commit/06b0dec07e0134c26dff17951390b5509a8ba0aa)，仓库采用 [MIT](https://github.com/enricoros/big-AGI/blob/06b0dec07e0134c26dff17951390b5509a8ba0aa/LICENSE)，分发复制内容时需保留许可证所要求的版权和许可声明。可借鉴 [ModelsWizard.tsx](https://github.com/enricoros/big-AGI/blob/06b0dec07e0134c26dff17951390b5509a8ba0aa/src/modules/llms/models-modal/ModelsWizard.tsx) 的填 Key、保存、获取模型流程，[DeepseekAIServiceSetup.tsx](https://github.com/enricoros/big-AGI/blob/06b0dec07e0134c26dff17951390b5509a8ba0aa/src/modules/llms/vendors/deepseek/DeepseekAIServiceSetup.tsx) 的获取 Key 链接、高级地址、模型刷新及错误状态，以及 [IModelVendor.ts](https://github.com/enricoros/big-AGI/blob/06b0dec07e0134c26dff17951390b5509a8ba0aa/src/modules/llms/vendors/IModelVendor.ts) 的服务商元信息、配置校验、请求参数和模型刷新接口划分。工程判断：macai 作为原生 UI 主参考，Big-AGI 用于补充多服务商扩展结构；React 界面不能直接接入 SwiftUI，模型列表获取也不能替代真实生成测试。未运行该产品。
