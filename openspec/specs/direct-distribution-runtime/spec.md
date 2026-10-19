# direct-distribution-runtime Specification

## Purpose

保障官网／DMG 分发的 Jotway 在关闭主应用沙箱后仍能保持数据、偏好、授权及辅助进程的连续性。定义正式包的安全属性、非破坏升级与失败恢复边界，使跨应用摘录能力不会以静默重建历史或丢失配置为代价。

## Requirements

### Requirement: Direct distribution uses an explicitly configured runtime

官网／DMG 构建的已签名主应用 SHALL 不启用 App Sandbox。Developer ID 正式包 SHALL 使用 Developer ID 签名、Hardened Runtime、安全时间戳及有效 Apple 公证。个人开发者分发 SHALL 显式选择 ad-hoc 应用签名与未签名、未公证 DMG，公开如实标示其状态，保留文件完整性校验及在线更新的 Sparkle 签名；不得将其宣称为已公证或已通过 Gatekeeper 的正式包。应用 SHALL 保持既有 bundle identifier 与兼容签名身份，不以本方案生成 Mac App Store 包。

#### Scenario: Inspect a release artifact
- **WHEN** Developer ID 正式包进入公开发布检查
- **THEN** 实际签名显示主应用非沙箱，主程序与嵌套代码的签名及 Hardened Runtime 校验通过，公证与 Gatekeeper 验证通过；缺失任一发布条件不得发布

#### Scenario: Developer build without distribution credentials
- **WHEN** 只构建本地开发包，或已选择 Developer ID 模式但所需证书／公证条件不可用
- **THEN** 可保留明确标示的开发产物，但不得自动降级签名身份、宣称正式包合格或绕过发布检查

#### Scenario: Personal developer explicitly publishes without Apple distribution credentials
- **WHEN** 个人开发者显式选择 `--ad-hoc` 发布且未提供 Apple 证书或公证凭据
- **THEN** 构建 ad-hoc 签名应用和未签名、未公证 DMG，校验 DMG、SHA-256 与 Sparkle 更新签名，在 Release 与下载页标示实际状态，不请求 Apple 公证或伪造其验证结果

#### Scenario: Local signing identity has no Apple Team ID
- **WHEN** 本地开发包或显式个人分发包使用 ad-hoc，或本地开发包使用没有 Apple Team ID 的自签名身份
- **THEN** 保留 Hardened Runtime，仅主应用使用临时生成的 library-validation 例外以加载内嵌 Sparkle；OCR helper 的独立沙箱不变，Developer ID 正式发布校验必须拒绝该例外

#### Scenario: Signing identity has an Apple Team ID
- **WHEN** 本地开发包或正式包的签名包含 Apple Team ID
- **THEN** 主应用保留 library validation，不生成本地加载例外

#### Scenario: Distribution artifact contains the local loading exception
- **WHEN** Developer ID 正式发布检查发现主应用启用了本地 library-validation 例外
- **THEN** 拒绝该产物，不进入公证或发布流程

### Requirement: Upgrade preserves existing application state before normal startup

首次运行非沙箱版本时，系统 SHALL 在任何业务存储、偏好默认值、凭据或采集启动前，确定本应用旧容器与直发数据位置并完成一次升级迁移。迁移 SHALL 保留数据库、历史、Notes 索引及归集／补标题状态、Codex 任务、完整性状态、Jotway 自有凭据和持久化偏好。显式关闭、未知旧偏好及缺失值语义 SHALL 保持，不因默认值覆盖。只有确认不存在旧状态的新安装才能初始化新状态。

#### Scenario: Existing install with disabled collection
- **WHEN** 用户旧版保留历史、配置、凭据，且关闭剪贴板采集或本地操作记录
- **THEN** 升级完成后的对应内容与关闭选择仍有效，主题、快捷键、模板、目标及最近文档引用保留，不被当成首次安装或重新采集启动前剪贴板

#### Scenario: Fresh direct installation
- **WHEN** 确认没有旧容器状态和已建立的新数据
- **THEN** 在直发数据位置正常初始化，继续使用既有新安装默认值，不导入其他应用内容

### Requirement: Migration is resumable and never silently replaces conflicting data

迁移 SHALL 先建立独立暂存副本、验证完整性，再提交数据与偏好；完整成功之前不得启动业务。源应用仍运行、旧状态不可读、复制／验证失败或新旧位置冲突时，系统 SHALL 保留两侧内容，显示可恢复原因并提供重试；不得覆盖、自动合并、伪装成功或静默回退为空库／默认配置。中断后 SHALL 从可识别的迁移阶段恢复，完成后不得再次覆盖新状态。

#### Scenario: Permission failure or conflicting roots
- **WHEN** 旧容器读取被系统拒绝，或新旧位置均有不同数据且没有可继续的迁移记录
- **THEN** 只展示迁移恢复入口，不开启业务存储、采集或 action；原数据保留，重试前不会生成一套替代历史

#### Scenario: Crash between data and preference adoption
- **WHEN** 暂存、数据提交或偏好提交期间进程退出
- **THEN** 重启识别已完成阶段并验证后继续，既不重复追加数据库内容，也不把已经提交的新状态覆盖回旧版本

#### Scenario: Reopen after successful migration
- **WHEN** 迁移完成后用户修改设置并产生新内容，再次启动
- **THEN** 使用新位置的最新状态，旧容器不再次导入或覆盖新偏好

### Requirement: Migration preserves recoverable source and complete persistence state

迁移 SHALL 只处理本应用拥有的数据，不删除或修改原容器；复制的数据库 SHALL 包含已提交但尚未合入主文件的状态。副本验证 SHALL 不输出正文、凭据或完整偏好到日志。凭据副本 SHALL 保持本用户所有及限制性访问权限。原容器仅代表迁移前快照；回退旧版 SHALL 明确保护迁移后的新内容，不自动逆向同步或声称旧快照包含新写入。

#### Scenario: Database has committed journaled data
- **WHEN** 旧数据库具有已提交的事务日志，随后执行迁移
- **THEN** 新位置可读到全部已提交内容，源文件及日志保留原样，完整性验证通过后才启用业务

#### Scenario: Credentials or paths fail validation
- **WHEN** 数据副本含不符合所有权／访问权限要求的凭据，或不安全的文件链接
- **THEN** 迁移不被标记为完成，不读取其他应用凭据，不打印敏感值，提供可重试失败状态

#### Scenario: Return to the previous application version
- **WHEN** 用户需要在迁移后恢复旧版
- **THEN** 保留原容器和新位置；在明确备份／迁回新增内容前，不通过覆盖文件或再次导入旧快照实现自动回退

### Requirement: Existing helper capabilities survive the runtime transition

关闭主应用沙箱后，OCR SHALL 继续在独立受沙箱限制的本地辅助进程中识别，保持既有载荷上限、超时、取消和退出语义，主应用不加载识别引擎。Codex SHALL 继续识别既有本用户脚本安装与 CLI 配置，探测和执行使用同一有效路径，不要求重新登录、覆盖用户脚本或重跑安装；Notes／Chrome 授权的使用边界保持原规则。

#### Scenario: OCR completes or is cancelled in the packaged app
- **WHEN** 非沙箱主应用处理一份符合条件的图片，或识别超时／被取消
- **THEN** 独立沙箱 OCR 子进程可取得本次输入并返回结果，超时／取消会被回收，不要求主应用或 helper 获得全磁盘访问

#### Scenario: Existing Codex setup remains usable
- **WHEN** 用户已有有效 Codex 脚本安装、CLI 和配置，升级后执行既有可用性检查
- **THEN** 检查与执行引用原安装；缺失或不可用仍按既有配置／可用性规则提示，不自动安装、登录或替换脚本

### Requirement: Existing authorization is preserved without resetting system consent

升级 SHALL 保持 bundle identifier 和签名身份连续性，并验证原 Notes／Chrome 授权与新增辅助功能授权各自独立。系统 SHALL 不自动重置系统授权数据库、移除既有授权项或为获取选区而要求其他无关权限；系统要求重新授权时 SHALL 仅提供对应的主动恢复入口，不假定签名不变即可保证授权延续。

#### Scenario: Authorization needs renewal after upgrade
- **WHEN** 已签名升级包运行后某项系统授权不可用
- **THEN** 只提示并允许用户主动恢复该项授权；其他功能仍按各自可用性运行，不通过全局权限重置解决
