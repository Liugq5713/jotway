# Spec Delta

## ADDED Requirements

### Requirement: Permission status refreshes for the running application

Jotway SHALL 在设置页显示、设置窗口激活、设置可见时应用重新激活及用户点击“再次检查”时，被动刷新当前运行进程的辅助功能权限。有限重查 SHALL 在三秒内结束，不重叠运行刷新任务，也不请求授权。只有当前进程的成功 trust 检查 SHALL 显示权限可用。设置离开可见状态时 SHALL 取消待执行的重查。

#### Scenario: Return after granting access
- **WHEN** 用户在 macOS 开启辅助功能权限后返回 Jotway 设置
- **THEN** 设置重新检查；当前进程获信任时显示权限可用，下次符合条件的快捷键唤起尝试捕获选区，无需再次点击 Allow

#### Scenario: Delayed or unavailable access
- **WHEN** 从 macOS 设置返回后的首次被动检查仍为 false
- **THEN** Jotway 在有限窗口内重查，随后显示当前运行应用仍无法访问选中文字并提供恢复说明，不无限停留在检查中

#### Scenario: Access is revoked or checks overlap
- **WHEN** 权限被撤销后用户返回，或连续点击“再次检查”
- **THEN** 只有最新检查可发布结果；显示不可用状态，旧成功结果不能覆盖它

### Requirement: Unavailable permission has actionable recovery guidance

当前进程权限不可用时，设置 SHALL 准确描述该状态，不断言用户从未开启权限。设置 SHALL 提供“再次检查”、既有主动授权及系统设置入口，以及核对所打开 Jotway 副本的简短步骤。本机界面 SHALL 显示运行应用的位置以帮助辨认。恢复说明 SHALL NOT 自动重置权限、移动应用、重启或丢弃草稿。

#### Scenario: User enabled permission but access remains unavailable
- **WHEN** 被动重查仍报告权限不可用
- **THEN** 设置说明 macOS 尚未让当前运行应用取得访问权限，引导核对授权条目及运行副本后再检查；可选重启说明先提醒保存未保存的草稿

#### Scenario: Running copy uses a temporary location
- **WHEN** 当前 Jotway bundle 位于 AppTranslocation 临时位置且权限不可用
- **THEN** 说明标明临时运行位置，建议先保存草稿再打开预期的已安装副本，不声称该路径证明故障原因，也不改变安装

#### Scenario: Authorization stays explicit
- **WHEN** 设置显示、执行被动刷新或点击“再次检查”
- **THEN** 不请求系统授权弹窗、不读取外部选中文字；Notes 与 Chrome 权限保持独立

### Requirement: Capture permission and browser capability remain distinct

每次符合条件的快捷键捕获 SHALL 独立重新检查当前进程权限。权限不可用结果 SHALL 更新共享权限状态；控件不支持、无选区、读取失败及超时 SHALL NOT 将权限标记为拒绝。确认授权 SHALL 只移除自有过期权限提示，保留其他错误。既有唤起、草稿、剪贴板及选区隐私规则 SHALL 保持有效。

#### Scenario: Granted access but unsupported webpage control
- **WHEN** 当前进程权限可用，但浏览器不提供选中文字
- **THEN** 设置继续显示权限可用，不引入权限拒绝提示，普通唤起遵循既有回退规则

#### Scenario: Successful capture after recovery
- **WHEN** 当前进程权限恢复，用户在支持的浏览器控件中划选文字，并以既有快捷键唤起隐藏的快捷输入面板
- **THEN** 新选区作为可撤销引用只追加一次，保留原草稿和目标，不重放旧选区

#### Scenario: Permission changes after Settings was checked
- **WHEN** 设置曾显示权限可用，而下次快捷键捕获观察到权限不可用
- **THEN** 共享状态更新为不可用，草稿按既有非阻塞提示及回退规则打开
