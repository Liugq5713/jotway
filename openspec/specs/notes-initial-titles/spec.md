# notes-initial-titles Specification

## Purpose

让新建备忘录第一次获得能够概括原文主题的 AI 标题，在接口暂时失败时保留完整正文并继续恢复标题，同时确保后续追加、应用重启和用户手动编辑不会导致重复保存或覆盖用户内容。

## Requirements

### Requirement: Initial semantic title

系统 SHALL 为改动生效后每篇新建笔记使用 fast 能力概括首次原文的主题，覆盖归集新建与普通新建。合法归类结果已含合格标题时 SHALL 复用，不重复请求。标题 SHALL 使用原文语言，单行、非空、最多 48 字符，不含 HTML、生成日期或寒暄；提示 SHALL 引导简短主题名称，避免照搬口语开头。标题完成后 SHALL 保持稳定，后续追加与补充不重新生成。

#### Scenario: Summarize a conversational capture
- **WHEN** 新笔记原文为“感觉 jotway 不可爱，哈哈，不知道可不可以设置一个形象，icon 有点丑”
- **THEN** 标题概括为类似“Jotway 形象与图标设计”的主题，完整口语原文仍各一次保存在正文中

#### Scenario: Reuse or independently generate
- **WHEN** 归类返回合法 new 标题，或普通新建/归类降级尚无可用标题
- **THEN** 前者直接采用；后者独立请求首次标题，不凭归类失败认定标题也只能截取正文

#### Scenario: Append after title completion
- **WHEN** 已有笔记的标题已完成，新原文追加或 AI 补充刷新
- **THEN** 保留已完成标题，不发起另一轮首次标题生成

### Requirement: Bounded title attempts and temporary title

没有合格标题时，系统 SHALL 对临时网络错误、限流、服务故障、超时和无效标题进行有限重试；每轮最多三次请求，总计最多 30 秒，包含排队和退避。重试耗尽或缺少有效配置时 SHALL 以“标题待生成”（非中文为“Title pending”）保存完整原文并登记待办，SHALL NOT 使用本地正文截取作为标题。认证、余额或请求不可修复错误 SHALL 暂停请求直到配置恢复；取消或失效 SHALL 不自动重试。

#### Scenario: Transient failure recovers
- **WHEN** 首次标题请求遇到 503，下一次在预算内返回合法标题
- **THEN** 使用该标题，只创建一次笔记，不把模型重试当作重复提交

#### Scenario: Repeated failure still saves the capture
- **WHEN** 三次请求均失败或本轮 30 秒期限到期
- **THEN** 原文按原有保存确认规则存入一次，使用临时标题并保留待补状态；迟到结果不直接写入或创建副本

#### Scenario: Missing or invalid credentials
- **WHEN** 没有密钥或服务明确拒绝认证
- **THEN** 保存完整原文和临时标题，不循环发送同一无效配置；配置恢复后可继续当天待办

### Requirement: Durable pending title recovery

原文确认保存后的待补标题 SHALL 独立于 AI 补充开关恢复，按退避时间后台续试；同一笔记最多一项待办，最多一轮在途请求。系统 SHALL 持久保存非正文身份、状态及重试时间，当天重启后从 Notes 验证读取首次原文继续，不新增本地正文副本。跨日、目的地失效或用户编辑 SHALL 停止自动补写；升级 SHALL 不为既有笔记建立追溯待办。

#### Scenario: Resume after restart
- **WHEN** 临时标题笔记已确认保存，当天重启且笔记与配置仍合法
- **THEN** 到期后恢复标题请求，不重复保存正文，也不发送新的保存完成通知

#### Scenario: Later entries arrive before title recovery
- **WHEN** 临时标题笔记收到新原文或更新了 AI 补充，先前标题请求随后返回
- **THEN** 标题仍概括首次原文；采用前读取并核对最新版本，保留全部新增原文及最新补充，不写回旧正文快照

#### Scenario: Day expires or user changes the note
- **WHEN** 笔记已成为往日，或检测到用户改名、改正文、移动、删除、锁定、共享或增加附件
- **THEN** 停止自动补标题，不覆盖用户改动，不创建替代笔记；已保存正文保持不变

#### Scenario: Recovery metadata cannot be persisted
- **WHEN** 原文需要应急独立保存，但安全身份与完整版本记录无法落盘
- **THEN** 保全原文并使用临时标题，明确记录恢复不可用；不安排无法验证所有权的自动补写，不把应急保存报告为标题恢复成功

### Requirement: Confirmed title replacement

系统 SHALL 仅在原文保存确认后补标题，更新前验证真实身份、文件夹、当天范围和完整内容版本，更新后回读确认。标题更新与原文追加、补充写回 SHALL 串行协调。更新结果不明时 SHALL 保留待核实状态，先回读核对，SHALL NOT 盲目重写或重建。原文保存成功与标题失败 SHALL 独立报告，标题失败不恢复已保存草稿。

#### Scenario: Uncertain update outcome
- **WHEN** 补标题写入已发出但响应丢失
- **THEN** 先回读核对新旧完整版本；已写入则结算完成，无法证明时保留不确定状态，不重复创建笔记

#### Scenario: External edit detected before dispatch
- **WHEN** 最终写前校验发现完整正文或标题与管理版本不同
- **THEN** 放弃补标题，保护现有笔记；不依据可见“标题待生成”文字推断写入权限

### Requirement: Content-free title diagnostics

系统 SHALL 单独记录首次标题的尝试次数、耗时、错误类别、待重试/暂停/完成/冲突/过期/不确定状态及是否确认采用，并可区分模型成功与 Notes 写入成功。日志 SHALL 不含正文、标题、Notes 标识、原始响应或凭证；日志故障 SHALL 不阻断原文保存。

#### Scenario: Explain a temporary title
- **WHEN** 原文已保存，而标题因服务故障等待恢复
- **THEN** 诊断明确区分保存成功、标题失败和下一轮重试安排，不将临时标题计为 AI 总结成功
