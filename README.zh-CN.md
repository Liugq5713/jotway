<p align="center"><img src="Resources/Icons/AppIcon.png" width="96" alt="Jotway 图标"></p>

# Jotway

**快速写下，存入 Apple 备忘录。**

Jotway 让你在 Mac 上随时唤起一个小面板，写下想法、提醒，或几行会议记录，写完继续手头的事。记下的内容保存在 Apple 备忘录里。

[English](README.md) · **简体中文**

需要 macOS 15 或更新版本。本文描述当前源码构建，下载版本的行为可能有所不同。

## 写一条备忘录

1. 按全局快捷键，唤起面板。
2. 写下想记住的内容。
3. 确认目标为 **Save to Notes**，按 **Enter**。

Jotway 在后台完成存入，你可以到选定的 Apple 备忘录文件夹查看结果。无论新建备忘录，还是启用按天归集后追加到相关备忘录，都会完整保留原文。

## 用模板，更快开始写

想记录一个想法、梳理一个问题时，可以从模板开始。

1. 在空白的快捷输入面板输入 `@`，选择模板。
2. 按提示填写，**Tab** 跳到下一项，**Shift+Tab** 返回上一项。
3. 写好后确认 **Save to Notes**，按 **Enter** 存入。

内置模板默认名为**记录想法**和**梳理问题**。选择模板只填入草稿，存入仍需你确认。

比如，“记录想法”会依次引导你写下：想法、为什么值得做、下一步。

在 **Settings → Templates** 中可以修改内置模板，也可以新增自己的模板。把会议记录、每日复盘等常用格式存成模板，下次直接填写。

## 首次设置

1. 在欢迎引导中设置全局快捷键。
2. 打开 **Set Up Notes**，点击 **Allow Access**，允许 Jotway 通过 macOS 自动化访问 Apple 备忘录。
3. 回到原草稿，再按一次 **Enter** 存入。

设置时会选定默认备忘录文件夹。之后可在 **Settings → Apps → Apple Notes** 中更改。详见[首次使用](docs/product/first-use.md)。

## 写的时候

切换到**临时便签**，让草稿保持在其他窗口上方，边做事边写。两种模式共用同一份文字，准备存入时切回快捷输入即可。

- **Shift+Enter** 换行。
- 隐藏面板后，再次唤起可继续写。
- 草稿在 Jotway 运行期间保留在内存中；退出、崩溃或重启应用会清空未提交草稿。

## 文字与隐私

输入时不请求 AI 模型。备忘录标题生成使用已配置的 AI 服务；归集、写作补充和相关历史也可能发送相关文字。配置了备用模型时，相同内容可能发送给第二家服务，并分别计费。

启用本地操作记录后，未提交草稿也可能保存在本机，默认保留 90 天。采集、导出和清理方式见[设置](docs/product/settings.md)。

## 从源码构建

需要 Swift 6.2 和 macOS 26 SDK。

```bash
swift build
swift test
./scripts/build-app.sh
```

参阅[文档入口](docs/jotway.md)、[开发环境](docs/development/environment.md)及[第三方声明](THIRD_PARTY_NOTICES.md)。

## 许可证

GNU General Public License v3.0，见 [LICENSE](LICENSE)。
