# clipboard-history Specification

## Purpose

让用户在快速记录面板内找回本机此前复制的文字和图片，通过文字或图片内识别文字筛选，再显式复制所选内容。该能力定义采集、保留、异步识别及失败恢复的边界，不改变普通草稿的纯文字契约。

## Requirements

### Requirement: History capture is explicitly enabled and local

系统 SHALL 在没有保存采集偏好时默认开启历史采集；已保存的开启或关闭选择优先，跨重启保持。在 Settings → Actions → Clipboard 提供采集开关并说明文字、图片及 OCR 文字会持久化在本机。打开列表不改变采集偏好；关闭采集停止内容读取和 OCR，保留已有历史供搜索与复制。进入显式 Clipboard 历史列表后的查询、历史内容或 OCR 结果 SHALL NOT 发送到网络或自动意图识别服务。字面的 `@clipboard` 无论旧显示偏好如何均不构成历史入口。

#### Scenario: First use without enabling capture
- **WHEN** 用户未保存过采集偏好并启动应用，包括从旧版本升级后仍无偏好
- **THEN** 采集默认开启，后续观察到的支持内容进入历史；首次打开列表显示采集状态，启动前已有的剪贴板内容不补录

#### Scenario: Enable capture then restart
- **WHEN** 用户启用采集、复制支持内容并等待采集完成，然后重启
- **THEN** 开关与历史仍在；未运行或关闭期间的旧复制不补录，启动以当前剪贴板版本建立观察基线

#### Scenario: Disable capture while OCR is running
- **WHEN** 关闭采集且仍有图片等待或正在识别
- **THEN** 停止新增采集，取消待处理识别并丢弃迟到结果；已有图片仍可复制，再开启后可恢复未完成识别

#### Scenario: Preserve disabled preference after upgrade or restart
- **WHEN** 已保存关闭选择，随后升级或重启并打开列表
- **THEN** 采集保持关闭，不读取内容建立新历史或启动 OCR；已有历史仍可搜索和复制，重新开启才恢复采集

#### Scenario: Default collection is disabled manually
- **WHEN** 默认开启后用户关闭采集，再重启
- **THEN** 关闭选择已保存且继续生效，不因默认值覆盖

### Requirement: Supported clipboard observations become bounded history items

系统 SHALL 在采集开启且应用运行时保存实际观察到的非空纯文字或 PNG/TIFF 栅格图片；不承诺捕获轮询间的所有复制。单次剪贴板版本最多形成一条记录，图片优先于同项文字，忽略文件 URL 项及已标记为临时或机密的项；多项剪贴板取顺序中的首个合格项。文字保留原始空白，图片复制保留所存图片表示。

#### Scenario: Capture text and image representations
- **WHEN** 观察到纯文字，或同时含 PNG/TIFF 和文字替代表示的一个图片项
- **THEN** 分别产生文字记录或一条图片记录；文字不被裁切或改写，图片不被降为文字记录，同次变化不会产生多个重复项

#### Scenario: Skip unsupported or excluded observations
- **WHEN** 剪贴板包含文件 URL、仅富文本无纯文字表示、空白文字、无法解码图片或临时/机密标记
- **THEN** 相应项不进入历史、不启动 OCR；无合格项时历史不变，普通编辑器粘贴仍遵循既有规则

#### Scenario: Duplicate content is copied again
- **WHEN** 新观察项与已有项的类型及保存内容完全一致
- **THEN** 更新该项最近复制时间并移到最近位置，不新增一条，不重复识别已完成的图片

### Requirement: Retention is bounded and clearing is complete

系统 SHALL 按最近复制时间保留最多 200 条，并将文字、原图、缩略图和 OCR 文字的持久化载荷合计限制在 200 MiB；超出时淘汰最旧项。单条文字上限 1 MiB UTF-8，图片保存表示合计上限 20 MiB、解码像素上限 4000 万；超限跳过并显示可理解的状态。提供独立的清空历史入口，删除所有历史及派生数据，不修改当前系统剪贴板。

#### Scenario: Limits evict or reject content
- **WHEN** 保存新项会超过总条数或载荷预算，或单项本身超出单项限制
- **THEN** 前者移除最旧项及其派生数据，后者跳过该项并记录不含正文的状态；不静默截断文字或缩小用于恢复的原图

#### Scenario: Clear during background processing
- **WHEN** 用户确认清空，且旧图片仍在采集转换或 OCR 队列中
- **THEN** 列表立即失效，已有持久化内容和缓存被清除，旧任务不能重新写回；当前剪贴板不变且不会仅因清空而重新采集，后续新的外部复制仍可采集

#### Scenario: Storage cannot persist history
- **WHEN** 本地存储读取或写入失败
- **THEN** 显示存储不可用或保存失败，不宣称内容已持久化；不影响普通 action，恢复后只对有效保留项提供复制

### Requirement: Images become searchable through asynchronous local OCR

系统 SHALL 在图片已可浏览和复制后，于后台本地识别中英文文字并缓存结果。识别中、完成但无文字、识别失败 SHALL 可区分；一次只处理一张；用户停止键盘/鼠标输入至少 2 秒后才启动下一项，识别在独立辅助进程内进行，每项结束即退出。超时或取消须回收子进程，搜索不得触发重复识别。OCR 结果仅用于搜索，不替换图片复制内容；识别错误不阻塞图片浏览、选择或复制。

#### Scenario: Search before and after recognition
- **WHEN** 图片含“会议”且 OCR 尚未完成，随后识别成功
- **THEN** 完成前空查询可见且可复制原图；完成后查询“会议”能够命中该图，当前筛选自动更新而不要求重新输入

#### Scenario: No recognized text or OCR failure
- **WHEN** 图片没有可识别文字，或识别失败
- **THEN** 保留可复制图片及对应状态，不伪造搜索文字；失败不无限自动重试，无文字与失败不被混为同一结果

#### Scenario: Stale OCR result arrives
- **WHEN** 项已淘汰、历史已清空或采集已关闭后旧识别结果到达
- **THEN** 不恢复已删项、不更新失效会话、不将旧结果写入新的历史代次

### Requirement: Clipboard retains its local list without a manual target entry

系统 SHALL 保留 Clipboard 的注册、本地查询与精确复制能力、采集、设置及已有数据，但手动目标菜单与键盘轮换 SHALL 不提供 Clipboard，不新增替代历史入口，也不以旧 `@clipboard` 前缀、普通意图建议或默认 action 进入。Clipboard 为当前目标时，其列表 SHALL 以空查询显示全部保留项，最近在前；按全部可见草稿文字查询，匹配正文及已完成 OCR 文字，忽略大小写，以空白分词且所有词均需包含匹配。旧前缀不删除；无匹配时显示空状态且禁止复制。模板菜单优先于历史结果，回填只更新本地查询。

#### Scenario: Manual target selection omits Clipboard
- **WHEN** 用户打开底部目标菜单或使用键盘轮换目标
- **THEN** 手动候选仅提供适用的 Notes 和 Codex，不出现 Clipboard 或替代历史入口；Clipboard 采集、设置与已有数据保持不变

#### Scenario: Complete mention replaces completion menu
- **WHEN** 用户从 `@clip` 输入到完整 `@clipboard`，无论旧偏好如何
- **THEN** 不进入历史或 action 补全；若无同名模板匹配则继续普通草稿，不新增历史入口

#### Scenario: Query text and OCR together
- **WHEN** Clipboard 为当前目标，查询为 `meeting link`
- **THEN** 返回正文或 OCR 同时包含两词的记录；缩略图代表原图，来源应用名称或“图片”等界面标签不参与正文匹配

#### Scenario: Recognition is unavailable
- **WHEN** Clipboard 为当前目标，AI 服务不可用或断网，但历史存储可用
- **THEN** 本地查询仍可筛选缓存文字并复制；无匹配不回退 Notes 或发起模型请求

#### Scenario: Hidden mention does not open history
- **WHEN** 没有显式 Clipboard 目标，用户输入 `@clipboard meeting link`
- **THEN** 无论旧隐藏偏好如何都不打开历史、不读取历史作为上下文；文字按普通路由处理，采集开关和已有历史不变

#### Scenario: Explicit Clipboard target remains local
- **WHEN** Clipboard 为当前目标，用户输入或通过模板回填包含 `@clipboard` 的查询
- **THEN** 全部字符参与本地搜索，不调用 Jev，不剥离前缀；模板确认只回填，不复制当前或旧高亮结果

### Requirement: History list preserves keyboard and selection continuity

系统 SHALL 在编辑区下方同一个有界列表内显示文字摘要、图片缩略图及状态；默认高度 300 pt，空间不足时缩小，长列表内部滚动。↑↓ 移动高亮，点击行选择，Enter 或 Command+Enter 复制。查询变化时选首个结果；后台新增或 OCR 更新时保留仍有效的选中项身份，不因行号变化选中另一项。组词期间按键优先交给输入法。

#### Scenario: Navigate while results update
- **WHEN** 用户已选中一个结果，后台新增记录或 OCR 完成导致列表变化
- **THEN** 选中项仍在结果中则保持其身份；被删除或不再匹配则清除选择，本次旧确认无效，下一次明确导航或新查询才能选择其他项

#### Scenario: Compose and cancel
- **WHEN** 中文组词时按 Enter/Esc，或组词结束后按 Esc
- **THEN** 前者交给输入法且不复制；后者关闭面板并按普通草稿规则保留查询，再次打开恢复查询与有效结果，不恢复失效高亮

#### Scenario: Accessible list and bounded layout
- **WHEN** 用户用 VoiceOver 阅读列表，或在窄窗浏览长文字与大图
- **THEN** 可获知记录类型、文字摘要或图片尺寸、OCR 状态及选择状态；缩略图不撑大窗口，输入区和确认入口仍可操作

### Requirement: Confirmation copies the selected payload exactly once

系统 SHALL 在确认时冻结当前有效选择与内容；文字复制完整原文，图片复制图片表示，不复制缩略图、OCR 文字或搜索词。仅写入成功后清理本次查询、收起面板并返回之前的应用，不自动粘贴；失败保留查询与可恢复选择，显示原因。无选择、失效选择和连续按键重复 SHALL NOT 触发误复制。

#### Scenario: Restore text or image
- **WHEN** 用户对一个有效文字或图片项确认
- **THEN** 系统剪贴板包含所选完整文字或图片，下一次普通粘贴能使用它；成功后面板关闭，不发送粘贴按键

#### Scenario: Payload unavailable or write failure
- **WHEN** 项在确认前已删除、载荷损坏，或系统剪贴板写入失败
- **THEN** 不报告成功、不收起面板、不改用另一项；读载荷失败时不先清空当前剪贴板，写入阶段失败则如实提示并允许用户重试

### Requirement: Clipboard restore does not feed other capture paths

系统 SHALL 识别自身历史恢复写入，避免再次采集成新项、重复 OCR 或成为下次面板打开的近期剪贴板引用；之后外部复制同样内容仍按正常采集处理。历史正文、图片及 OCR 文字 SHALL NOT 写入本地操作记录、诊断或其导出；查询草稿及执行状态继续遵循既有操作记录开关。普通 action、纯文字编辑及其他下方区域保持原行为。

#### Scenario: Restore then reopen
- **WHEN** 从历史复制一项后立即重新打开面板
- **THEN** 本次恢复不会新增历史、启动 OCR 或向草稿自动插入引用；之后外部复制会产生正常的新观察

#### Scenario: Local operation recording is enabled
- **WHEN** 开启操作记录后搜索并复制图片或文字项
- **THEN** 记录可包含用户查询和成功/失败状态，但不包含被恢复载荷及 OCR 内容；日志清理与剪贴板历史清理彼此独立

### Requirement: Clipboard list omits settings navigation

系统 SHALL 在 Clipboard 历史列表内不显示 Settings 按钮或替代的设置跳转入口，覆盖有结果、空列表、采集暂停和存储错误状态；保留采集状态和错误提示。Settings → Actions → Clipboard SHALL 继续提供采集开关、本地存储说明和需确认的清空历史入口。列表选择、键盘操作与复制行为继续遵循现有规格，模板菜单打开时不执行复制。

#### Scenario: Open list in any collection state
- **WHEN** Clipboard 为当前目标，不论采集开关、结果数量或存储错误状态
- **THEN** 列表无设置跳转入口，采集状态与错误或空状态仍可见；有效历史的选择和复制保持原有行为

#### Scenario: Manage collection through application settings
- **WHEN** 用户打开 Settings → Actions → Clipboard
- **THEN** 可切换采集、阅读本地存储说明并发起需确认的清空；取消保留历史，确认不修改当前系统剪贴板
