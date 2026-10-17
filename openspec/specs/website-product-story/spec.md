# website-product-story Specification

## Purpose

让官网访客通过 Apple Notes、Calendar 和 Reminders 的具体工作场景理解 Jotway 的价值，并能区分基础存入、可选 AI 与只读问答。统一约束网页演示的真实性、能力适用条件、可访问性和下载路径，避免把实现机制或未交付功能当作产品收益。

## Requirements

### Requirement: Apple workflows lead the product story

官网 SHALL 在首页主标题、首屏说明及主要场景突出 Apple Notes 和快速记录用途，次级说明可介绍 Notes-only Personal Agent、Codex 与 Clipboard。Calendar、Reminders、Chrome 搜索、ChatGPT 及 Jev SHALL 不再作为本次目标版本能力宣传；Chrome 网页来源仍可按实际条件说明。通用应用启动 SHALL NOT 占据首屏核心卖点位置。页面标题和描述 SHALL 与定位一致，网站继续使用英文；预览与当前下载版本须明确区分。

#### Scenario: Visitor arrives at the home page
- **WHEN** 访客打开面向本次目标版本的首页或标明版本的预览
- **THEN** 主标题附近能读到 Apple Notes 及记录想法的用途，并能找到下载或可用性入口，无需理解 Jev 或 action 才能理解产品

#### Scenario: Visitor explores other capabilities
- **WHEN** 访客继续阅读次级说明或产品文档链接
- **THEN** 能发现保留的 Codex、Clipboard 及 Notes 问答，不把已移除 action 列为目标版本功能，也不声称本地应用启动已移除

#### Scenario: Visitor reads draft-sharing information
- **WHEN** 访客阅读目标版本的首页隐私说明或隐私页
- **THEN** 不再声称输入草稿会触发 Jev 分类或要求配置/删除 Jev 密钥；保留 Notes 辅助、问答、索引及本地操作记录的真实发送与留存说明，不宣称移除 Jev 后所有处理均在本机

### Requirement: Examples explain the destination and confirmation

官网 SHALL 提供 Notes 输入、用户确认和目标结果示意，遵循对应版本的 Current 行为，区分原文和可选 AI 补充。SHALL 移除 Calendar、Reminders、Chrome 搜索与 ChatGPT action 的演示及控制入口；确认前的草稿 SHALL NOT 被描绘为已保存。Notes 问答若展示，须与存入场景区分并遵守只读及覆盖条件。

#### Scenario: Notes example preserves the user's idea
- **WHEN** 访客阅读 Notes 场景
- **THEN** 能看到原始想法经确认进入所选 Notes 文件夹；相关笔记或 AI 补充若出现，须与原文分开并说明启用条件，不展示必然命中历史或改写原文的承诺

#### Scenario: Removed destinations have no active demonstration
- **WHEN** 访客浏览目标版本的场景选择、动效或静态降级内容
- **THEN** 不出现已移除 action 的可选示例、确认预览或成功结果，隐藏的旧脚本状态不能重新切换到这些演示

#### Scenario: Reminder example shows a due value
- **WHEN** 网站为本次目标版本生成演示内容
- **THEN** 不再生成旧 Reminders 截止时间示例及选择入口；旧场景名称仅用于追踪被替换的契约

#### Scenario: Calendar example shows a valid time range
- **WHEN** 网站为本次目标版本生成演示内容
- **THEN** 不再生成旧 Calendar 起止时间示例及选择入口，静态内容和辅助功能文本也不保留该预览

### Requirement: Personal context remains an optional read-only story

官网 SHALL 在核心存入场景之后介绍显式选择的 Personal Agent，仅使用允许范围的 Notes 已发布原文回答。SHALL 说明 AI 配置、Notes 索引及资料覆盖条件，不描述日历或提醒事项读取，不承诺全库实时覆盖、自动跨应用同步、代办事项或问答自动写回。日期问题 SHALL 不把笔记记录日期直接宣称为所述事件发生日期。

#### Scenario: Visitor reads a personal question example
- **WHEN** 页面展示从 Notes 整理线索的示例问题
- **THEN** 读者可识别这是需显式提问的可选 AI 功能，答案保持纯文字，不提供原生界面不存在的来源卡片或执行控件，也不暗示已读取系统日程或任务状态

### Requirement: Demonstrations are clearly illustrative and accessible

网页演示 SHALL 只使用预设虚构内容，并在可见位置标注为示意；不访问本机应用、不请求个人资料、不发送模型请求。保留的场景控制 SHALL 可用键盘操作，动态效果可暂停；核心内容 SHALL 不依赖脚本或动画才能阅读。单场景不必保留无用途的切换控件，已移除场景不得残留在降级内容或辅助功能文本中。

#### Scenario: Visitor selects and pauses examples
- **WHEN** 访客用鼠标或键盘操作仍提供的场景或动态效果
- **THEN** 输入和结果一致，焦点可见且不丢失；动画若播放则提供可发现的暂停方式，不逐字符轰炸读屏状态

#### Scenario: Reduced motion or JavaScript unavailable
- **WHEN** 访客启用减少动态效果或关闭 JavaScript
- **THEN** 保留场景的用途与结果仍以静态内容可读，下载和页面导航正常；减少动态效果时不自动播放打字、粒子或轮换

#### Scenario: Narrow viewport remains usable
- **WHEN** 页面宽度为 375 px，或桌面页面放大到 200%
- **THEN** 主要内容和控制按可用空间重排，没有遮挡、重叠或必须横向滚动才能访问的下载入口

### Requirement: Claims reflect availability and data boundaries

官网 SHALL 将功能描述与当前下载版本核对，无法确认的能力不得作为已提供功能宣传。首页 SHALL 简述系统授权与可选外部 AI 条件并链接到一致的隐私说明；隐私页 SHALL 区分本机存储、索引服务、Notes 辅助和问答服务及全文记录，明确本地目标匹配不发送 Jev 分类请求，不使用“所有资料只在本地”等不实承诺。

#### Scenario: Capability is present only in development
- **WHEN** 功能仅出现在工作区、独立提案或尚未确认包含该功能的发布版本中
- **THEN** 页面将其排除出当前可用功能及演示，或明确标为预览并说明所需版本；不因首页下载按钮可用就暗示已包含

#### Scenario: Visitor checks optional AI privacy
- **WHEN** 访客从 Notes 补充或 Personal Agent 区域进入隐私页
- **THEN** 能了解相关问题、资料或索引文本可能发往配置服务，关闭会话不等于删除本地全文调试记录；不会读到与首页冲突的日期解析、AI 回退或内存保留说明

### Requirement: Verified download and navigation remain intact

官网 SHALL 保持首页、下载页、隐私页以及项目子路径下的导航可用。下载地址、版本、系统要求、签名和校验信息 SHALL 继续来自已有验证元数据，禁止在宣传文案中维护第二套值；无公开安装包时 SHALL 保留可用性说明。

#### Scenario: Public download is available
- **WHEN** 构建使用已验证的公开发布元数据
- **THEN** 首屏、导航和结尾下载入口指向同一安装包，安装说明与隐私仍可到达

#### Scenario: No public download is available
- **WHEN** 构建使用未发布状态元数据
- **THEN** 入口引导至可用性和安装说明，不生成虚构下载地址、版本或兼容性承诺
