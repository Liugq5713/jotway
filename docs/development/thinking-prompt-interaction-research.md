# 思考提示的产品交互研究

> Role: **Reference**
> 调研日期：2026-10-17（Asia/Shanghai）
> 范围：写作、记录产品如何触发、展示、更新和关闭 AI 建议。

本研究服务于“保留自动触发，同时减少打扰”的选择，不定义 Jotway 当前行为或实施方案。依据公开官方帮助、教程与产品文章，未登录测试；“当前帮助”指现可访问的官方操作说明，不代表已实测所有客户端。本次未找到这些商业产品公开的具体防抖秒数；5 秒仅是下述研究原型的一项设置，不能当作市场惯例或已证实的最佳值。

## 主要对照

| 产品与证据类型 | 触发、位置、更新 | 用户控制与未知 |
| --- | --- | --- |
| **Type · Content Ideas**；较早官方教程（2025-01-31） | 官方描述建议随文档变化演进；点击右侧栏灯泡查看下一步写作建议。[Overview](https://blog.type.ai/post/type-ai-overview) | 循环图标或 More suggestions 换一批；右上图标收起侧栏。同一教程未说明防抖、默认开关、收起后是否继续生成；当前版本未登录核实。[操作说明](https://blog.type.ai/post/type-ai-overview) |
| **Mem · Heads Up**；当前帮助 | 新建或打开笔记时自动找相关笔记；用户打开右侧 Heads Up 页查看，可并排打开相关笔记。它是检索材料，不是追问。[Heads Up](https://help.mem.ai/features/heads-up) | Find More 继续查找；⌘⇧K 打开 Heads Up，`⌘\` 切换侧栏。未公开普通打字的防抖规则；Voice Mode 的实时关联不能外推为文字编辑机制。[快捷键](https://help.mem.ai/features/keyboard-shortcuts)、[Voice Mode 说明](https://get.mem.ai/features/heads-up) |
| **Grammarly**；当前帮助 | 自动检查以文本下划线和浮标数量提示，点击才展开建议卡。Editor 也提供右侧建议卡。[桌面指南](https://support.grammarly.com/hc/en-us/articles/4412816078349-Grammarly-for-Windows-and-Grammarly-for-Mac-user-guide)、[Editor](https://support.grammarly.com/hc/en-us/articles/360003474732-Grammarly-Editor-user-guide) | 可忽略建议、关闭某类建议。Strategic suggestions 会考虑读者疑问与信息缺口，并有 See ways to increase impact 开关；该功能限美式英语，不能假定其展示机制与语法检查完全相同。无公开防抖秒数。[Strategic suggestions](https://support.grammarly.com/hc/en-us/articles/25351804320397-Introducing-strategic-suggestions) |
| **Rosebud**；当前帮助 | Personalized Prompts 每日自动提供开篇问题，用户在 Home / Explore 选择；写作中的 Go deeper 是主动请求。Web Interactive 给观点加一个问题，Focused 给三个问题。[每日提示](https://help.rosebud.app/tools-for-growth/personalized-prompts)、[Dig Deeper](https://help.rosebud.app/tools-for-growth/dig-deeper) | “每日自动准备”与“打字中自动追问”要分开；上述帮助没有证明停写后自动弹出追问，也未给防抖或静默规则。[功能说明](https://help.rosebud.app/tools-for-growth/dig-deeper) |
| **Mindsera**；当前帮助与宣传存在差异 | 帮助描述 Go Deeper 按钮或 ⌘Enter 请求，Refresh 更新，可选 Conversational / Questions only。Minds Comments 则是加号菜单→选择→Generate，再点击批注查看。[Go Deeper](https://mindsera.com/help/editor/personalized-prompts-go-deeper)、[Minds Comments](https://mindsera.com/help/editor/minds-comments) | 宣传文章称实时反馈，但操作帮助明确有 Generate 步骤；目前不能确定哪些客户端具备自动生成、何时更新或如何暂停。[Mindsera 2.0](https://mindsera.com/articles/introducing-mindsera-2-0)、[2026 产品文章](https://mindsera.com/articles/best-journaling-apps-in-2026-12-tested-and-compared) |

这里的“自动”至少涉及三件不同的事：上下文跟着正文变化、系统准备候选内容、界面立即让用户看见。Type 的教程明确前后文关联与查看入口，却没有交代后台生成策略；Mem 则把新建、打开笔记作为具体情境。因此，应逐项记录触发事件与展示动作，不能仅凭“实时”一词补出完整流程。[Type](https://blog.type.ai/post/type-ai-overview)、[Mem](https://help.mem.ai/features/heads-up)

“未知”也不表示产品没有该能力；只是公开说明不足以核实。尤其是默认开启、关闭后静默多久、相似建议是否去重，需要客户端测试才能补齐。以下借鉴只采用已写明的交互，不据营销措辞推断这些细节。

## 补充对照与排除项

1. **Lex**：Checks 由用户打开、选类型，再点击文本高亮接受、修改或忽略。其写作方法建议初稿用 Focus Mode，卡住时输入 `+++` 续写。这是主动求助的对照，不能用来否定自动提示偏好。[Checks](https://lex.page/read/c563b895-d226-40c6-988f-33add2ff1dac)、[The Lex Method](https://lex.page/read/cd6c53cd-bd90-4d91-81c7-8dfc9eb53646)
2. **Day One**：工具菜单→Go Deeper→弹层选问题→插入正文；Esc 或点击外部关闭，刷新新增一页并保留前面的选项。它展示了可退出、可回看问题的做法，但不是自动追问先例。[官方指南](https://dayoneapp.com/guides/ai-features/go-deeper/)
3. **Napkin**：旧桌面原型已于 2026-06-30 关闭；当前 iPhone 产品强调主题关联与探索，未核实有打字中的自动追问，不把旧桌面演示当现状。[官网](https://napkin.one/)、[当前帮助](https://support.napkin.one/en/articles/16730476-how-napkin-works)

## 对 Jotway 的设计含义（推断）

**最值得借鉴的是把“自动生成”“引起注意”“替换当前提示”分开。** Type 的内容关联侧栏、Mem 的相关材料入口、Grammarly 的小标记再展开，分别提供不同先例；它们没有证明某一方案对快速记录面板最优。

1. **保留自动触发，固定展示位置。** 可试验编辑区下方的一行低强调提示，避免弹层、抢焦点或每次出现都改变布局。这是对现有思考提示形态的候选调整。
2. **延长停写等待作为实验。** 先比较不同等待时间与当前基线，不能把“停下”直接解释为卡住。中文组词结束、有效内容变化和请求合并需另行考虑。
3. **更新时保留旧提示。** 新内容在后台准备；内容近似时不替换，减少“写几个字就换题”。何谓有效变化、多久可再更新仍需试用确定。
4. **让关闭表达明确意图。** 可试验关闭后当前草稿不再自动出现，手动入口可恢复；这是本研究建议的控制方式，并非上述产品已证实的统一规则。

这些产品主要证明交互机制存在。自动检查、相关笔记与思考问题的阅读成本不同，不能把语法建议的更新频率直接搬给追问，也不能以建议打开率或新增字数证明思考质量提高。

## 一项相关研究原型

16 人一周的技术探针试验过停写 5 秒、句末加 1 秒等触发：先检查情境相关性，再显示小侧标，点击展开，忽略后 15 秒淡出。它是研究原型；5 秒不是行业标准，也未被证明最优。[作者全文](https://arxiv.org/html/2609.01588v1)

## 下一步比较

先做两种都保留自动触发的短时原型：**固定一行直接呈现问题**，与**固定一行只提示“有一个可想的方向”，点击展开**。先保持问题内容与触发等待一致，比较继续写时的干扰、实际有帮助的次数和主动关闭情况；确定呈现方式后，再单独比较等待时间，避免同时改变多个因素。
