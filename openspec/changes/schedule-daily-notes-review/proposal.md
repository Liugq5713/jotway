# Proposal

## Why

今天回顾目前需要用户主动打开才会读取和生成，无法在每天固定时间提前准备。用户希望自行设置每日运行时间，并明确选择：电脑睡眠或 Jotway 退出导致错过时间时，跳过当天，等待下一天。

## What Changes

- 在 Apple Notes 的笔记回顾设置中增加独立的自动今天回顾开关和每日时间选择，按本机时区运行，保留手动今天／周回顾入口。
- 到时在后台生成今天回顾，不打开面板、抢焦点或发送完成通知；再次打开今天回顾可复用有效任务或完成缓存。
- 错过时间不补跑，不唤醒电脑、不在应用退出后执行；同一本地日期至多受理一次自动运行。
- 自动运行沿用已有 Notes 授权、文件夹范围、原文边界与文本模型，不自动请求授权或扩大读取范围。
- 协调手动与自动请求，避免重复生成今天回顾，也不打断正在查看或生成的周回顾。

## Capabilities

### New Capabilities

无。

### Modified Capabilities

- `notes-review`：增加可设置的每日自动运行、错过即跳过及调度去重规则，扩展请求生命周期和缓存共享规则。

## Impact

- `Sources/Actions/NotesReview.swift`、`NotesReviewLibrary.swift`：生成生命周期、请求归属与缓存共享。
- `Sources/App/AppState.swift`、`JotwayApp.swift`：应用级调度的持有与启动。
- `Sources/Actions/AppleNotesAction.swift`、`Sources/Actions/Settings/ActionSettingsView.swift`、中英文资源：偏好、设置控件和隐私说明。
- `Sources/Features/Launcher/LauncherSession.swift`：按用户选择的周期映射回顾状态。
- `docs/integrations/apple-notes.md`、`docs/product/settings.md`：实现后更新当前行为。
- 仅新增本地调度偏好与去重标记；不新增依赖、系统后台服务或持久化笔记／回顾正文。
