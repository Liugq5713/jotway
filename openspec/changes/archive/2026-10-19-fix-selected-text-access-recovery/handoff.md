# 选中文字权限恢复交接

- 已实现：设置可见时被动检查，单轮最多三秒并可取消；再次检查不请求授权。当前进程权限与浏览器读取能力分开，捕获独立检查并在 MainActor 发布带时间顺序的证据，迟到结果不能覆盖更新检查。确认授权只清除自身权限提示，其他错误保留。
- 设置页提供当前运行路径、系统设置入口与手动恢复说明；AppTranslocation 只是线索。退出或重新打开前先保存草稿，不自动修改 TCC、签名、安装或草稿。
- 7/9 任务完成。4.2／4.3：人工验收未执行；用户已取消其强制门槛，非阻塞。真实权限恢复、浏览器版本／支持情况、窗口布局、键盘导航、VoiceOver、真实 IME 和选区撤销体验均未据此宣称通过。

验证：

- `swift build` 退出 0。首次构建因私有嵌套类型不支持 Observation 宏扩展失败，去掉无必要的宏后通过。
- VFS 仅将 `StorageLocation.userHome` 指向空临时目录；`swift build --build-tests -Xswiftc -vfsoverlay -Xswiftc <test-vfs.json>` 退出 0。执行通过 `sandbox-exec` 拒绝真实应用／Notes 数据、Keychain/securityd 和网络，合成路径读写与网络拒绝自检通过。
- 直接运行既有 xctest bundle：LauncherActionTests 8 项及 MainPathTests 的纯文字、Return、marked-text 三个无窗口用例，11/11 通过；未运行会创建 Panel 的其余用例。剪贴板 fixture 使用唯一 pasteboard，持久化与偏好使用内存／临时目录／独立 suite。
- `.git` 临时探针调用实际模块，28/28 合成断言通过：假 check/request/read 验证授权转移、持续 false、撤销、取消、重复刷新、迟到结果、提示所有权及能力错误区别。没有创建 App／Panel、调用真实授权、AX 读取、Notes 或真实模型。
- 静态核验 12 项通过，包含双语键、可见窗口门禁、草稿提醒、仅 Allow 请求及捕获原有 150 ms／去重／过期保护。未修改编辑器原生撤销路径。
- HEAD 加本项增量的 134 个 Swift source blob 整模块 typecheck 退出 0；工作树仍含未交付 Insight，工作树构建不是提交源码唯一证据。
- change strict 与全量主规格 strict 均退出 0，23 项主规格通过；同步新增 3 个需求、9 个场景，既有需求和 Purpose 完整保留。

完整命令、退出码、日志、候选 blob 清单与隔离证据保存在本轮 `.git/codex-openspec-queue/runs/02671d31-36c5-40cc-8571-befc03186215/selection-coder/`。无新增仓库测试。Instant Insight、独立流程文档及三份已授权格式修复保持未提交；同一增量应用于原基线后与当前本项文件逐字节一致。
