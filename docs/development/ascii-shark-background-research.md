# 编辑区鲨鱼背景动画可行性

> Role: **Reference**
> 调研日期：2026-10-20
> 上游快照：[stackedlol/ascii-sharks `c521e24a787e6d4cc460d4cf2b9815f25e4fe453`](https://github.com/stackedlol/ascii-sharks/tree/c521e24a787e6d4cc460d4cf2b9815f25e4fe453)
> Jotway 代码依据：`cd47d4fbf60b93d0dab88f87ee25a38b8784a54e`。本文记录源码事实和方案判断，不定义已实现行为。

**方案判断：可做，原生实现更适合 Jotway。** 用户希望编辑区像一个安静的鱼缸：输入时鲨鱼慢慢游到边缘，让出中间；停下来思考后再游回来。这需要随编辑活动改变路线，而非简单循环播放。上游已有自然转向和中央避让的基础，但没有输入活动接口，默认视觉与负载也偏向整页展示。更合适的方向是原创的一条紧凑 ASCII 小鲨鱼、原生绘制或原创序列帧，加一个简单的路线控制器。

## 上游实际提供什么

| 部分 | 源码事实 | 对接意义 |
| --- | --- | --- |
| `src/world.ts` | 鱼群模拟、捕食、重生和鲨鱼运动；每条鲨鱼有 20 个脊柱节点，支持 8 个品种。默认 4 条鲨鱼，鱼数按面积生成并限制在 85–340 条。[定义与初始化][world-init] | 可以参考运动结构；默认生态规模超过编辑区装饰的需要。 |
| `src/renderer.ts` | 把形体逐格栅格化，再用 Canvas 2D 的字符与色块绘制；鱼鳍随转弯变化，尾部随相位摆动。不是现成 GIF、视频或序列帧。[栅格化与绘制][raster] | 自然转身来自实时形体计算，移植完整视觉比移动一张图片复杂。 |
| `src/engine.ts` | 将模拟与渲染接入 DOM canvas；处理尺寸、鼠标、离开网页视口和减少动态效果。[引擎][engine] | 生命周期与浏览器环境耦合，不能直接作为 SwiftUI 组件使用。 |
| `src/math.ts`、`src/species.ts`、`src/index.ts` | 数学、鱼种参数和导出；另外有 `src/react.tsx`、`demo.ts`、`index.html`、`package.json`、`tsconfig.json`、README 与 `.gitignore`。[完整文件树][tree] | 核心源码规模约 1,845 行，React 包装另外 21 行。仓库没有原生 macOS 实现。 |

**依赖事实：** 核心没有 npm 运行时依赖，开发依赖是 TypeScript `^5.6.0` 与 Vite `^6.0.0`；包声明 `private: true`。React 包装需要宿主提供 React，且不在默认类型检查范围。示例 HTML 会请求 Google Fonts 的 Geist Mono；这一网络请求来自示例，不是模拟本身的必要条件，原生版本可使用本地等宽字体。[包配置][package]、[React 包装][react]、[类型检查范围][tsconfig]、[示例 HTML][html]

**授权事实：** 此快照的完整文件树没有 LICENSE，README 和 `package.json` 也没有许可声明；查询时 GitHub 仓库元数据的 `license` 为 `null`。这不足以确认可以把代码或按其代码导出的美术资源分发进应用。GitHub 说明公开仓库的可查看、可 fork 与开源许可是不同事项。若要复制、翻译移植上游代码或使用其派生资源，先取得明确授权；原创实现与原创美术是另一条路径。[文件树][tree]、[README][readme]、[GitHub 许可说明][licensing]

## “输入时退边、停顿后返回”的差距

**已有事实：** 鲨鱼会巡游、追鱼、避让其他鲨鱼；中央有一个软椭圆避让区，半径为画布宽度的 30% 和高度的 16%。转弯速度受限，速度也平滑变化。它们确实具备自然改变方向的基础。[运动算法][steering]

**尚缺事实：**

1. `OceanEngine` 的外部入口只有构造时传入 canvas 与 `{ kind, size }[]`，以及 `destroy()`；没有 typing/idle、目的地、速度、透明度或 pause/resume 接口。它把 `World` 设为私有。低层 `World` 和 `AsciiRenderer` 另有导出，因而可自行接线，但需要新增控制逻辑。[引擎][engine]、[导出][exports]
2. 鲨鱼的 `target` 指向鱼，不是任意位置。中央避让只作用于头部，且捕食时避让力变小；身体、尾巴和鱼群仍可能经过文字区域，不能把它当成文字保护机制。[对象定义][world-init]、[运动算法][steering]
3. 鼠标移动驱赶的是小鱼，点击会产生水花；没有键盘、编辑器或输入法活动监听。这些视觉反馈不适合直接绑定到正常文字选择或点击。[指针事件][engine]、[鱼群避让][fish-input]
4. 出界规则会把鲨鱼往画布中心拉回；让它长期待在边缘，需要协调这一规则和巡游/捕食行为。仅调整坐标或加强中央斥力，不能保证稳定退边。[运动算法][steering]

**设计推断：** 用“巡游 → 退边 → 边缘慢游 → 返回”表达运动状态即可。开始编辑时只更新目标区域，后续按键延长停顿计时，不反复重置动画。路线应优先通向附近边缘，避免为了退场横穿中间。停顿后降低中央避让权重并平滑恢复巡游；如果已有较多正文，仍应留在边缘，而不是在文字下穿行。

输入活动还应包括粘贴、删除和输入法组词；组词期间不能只凭正文未变就判断为空闲。选区拖动、滚动、菜单操作也应暂缓返回。以上是本次方案建议，尚未实现或验证。

## Jotway 的接入位置

**本地源码事实：** [EditorView.swift](../../Sources/Features/Editor/EditorView.swift) 的 `inputCard`（约 357 行）嵌入原生 `NSTextView`；scroll view 和 text view 已关闭 `drawsBackground`（989–1035 行）。[EditorCardBackground.swift](../../Sources/Features/Editor/EditorCardBackground.swift) 当前负责深色 material 与 95% tint，并关闭命中测试、隐藏于辅助功能（11–23 行）。因此可把装饰放在卡片底色之上、文字编辑器之下；位置应限定在 `inputCard`，因为共享 `cardChrome` 也用于下方卡片。

**本地源码事实：** `textDidChange` 更新正文绑定（1069–1071 行），`insertText`、`setMarkedText`、`unmarkText` 发出组词状态变化（1394–1416 行）；同文件 1084 行说明绑定值本身不是 Observable。可靠的活动信号应从原生编辑器协调器接入，不能只依赖 SwiftUI 的 `onChange`。

**本地源码事实：** [RecordPanel.swift](../../Sources/Window/RecordPanel.swift) 的 close/orderOut 会发出 `panelDismissed` 并停止 edge glow（172–186 行），但 `hideForGettingStarted` 直接调用 `super.orderOut`（199–203 行）。动画必须覆盖所有隐藏路径，可结合窗口可见性与 [occlusionState](https://developer.apple.com/documentation/appkit/nswindow/occlusionstate-swift.property) 停止调度；仅靠 SwiftUI `onDisappear` 或单个 dismissed 事件不够。

**规格约束：** [launcher-appearance](../../openspec/specs/launcher-appearance/spec.md) 当前明确排除纹理，并要求空输入只显示占位文字与光标。默认快捷输入宽 560 pt、最小宽 360 pt，输入卡片最小高 122 pt，编辑器最小高 52 pt。动画需要在未来实现时修改相关规格，且应先确认小尺寸下仍能看出鲨鱼。本文不改变现有规格。

**由源码计算：** 若只在文字视口后绘制，区域约为 520 × 52 个逻辑单位，上游 `cw = clamp(round(width / 124), 8, 13)` 得到 8，`ch = round(cw × 1.45)` 得到 12，即仅约 5 行字符。如果覆盖整张默认输入卡片，560 × 122 的区域也只有约 11 行，且需要避开动作行。默认 `size = 1` 时鲨鱼长度至少 170。原版形体细节在这些尺寸下能否保留，需要视觉验证；首版更适合紧凑 ASCII 轮廓，不为动画自动增大输入卡片。用户提出的输入页背景可以覆盖输入卡片，以文字与控件周围的保护区域限制路线，不必只挤在 52 pt 的文字视口里。这是几何约束与方案判断，不是视觉实测。[尺寸与间距](../../Sources/Window/LauncherMetrics.swift)、[格子尺寸][render]、[形体尺寸][world-init]

## 三条技术路径

| 路径 | 可行性判断 | 主要代价 |
| --- | --- | --- |
| 原生 Swift 绘制 | **优先考虑。** 使用 [SwiftUI Canvas](https://developer.apple.com/documentation/swiftui/canvas) 或 AppKit 绘制原创的紧凑 ASCII 鲨鱼，保留独立运动状态；易接入编辑活动与窗口状态。 | 完整复刻上游的逐格采样、鱼鳍和皮肤效果工作较多；复制或翻译其实现仍需先解决授权。 |
| 原创序列帧 + 原生路径移动 | **可做较小的首版。** 用少量 ASCII 游动帧表现尾巴，位置与朝向由原生代码控制，同样能退边和返回。 | 转弯自然度、缩放清晰度受素材限制；需要原创或有明确许可的透明素材。不能把上游画面导出成序列帧当作绕过授权的方法。 |
| 本地资源 `WKWebView` | **技术上可行，优先级较低。** 保留浏览器 Canvas 与模拟，通过桥接发送活动、可见性和尺寸。 | 对一个装饰层引入网页运行环境；还需修改透明背景、禁用鼠标效果、添加暂停与活动 API，并验证焦点及资源开销。不能直接嵌入示例网页就视为完成。 |

上述成本比较是架构判断，没有运行性能数据。原生调度可使用支持最小间隔与暂停的 [animation(minimumInterval:paused:)](https://developer.apple.com/documentation/swiftui/timelineschedule/animation(minimuminterval:paused:))；减少动态效果可读取 [accessibilityReduceMotion](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion)，改为静止或隐藏装饰。

## 视觉与资源成本

**上游源码事实：**

- 模拟固定为 60 Hz，每帧最多补 4 步；绘制由 `requestAnimationFrame` 驱动，没有独立帧率上限。因此不能将它称作“最多每秒绘制 60 次”。设备像素比限制为 2。[循环与尺寸][engine]
- 每帧重新栅格化鲨鱼包围区域：格子中心加 4 个子采样，并绘制字符与色块；同时更新鱼群、尾迹扩散等。空间哈希、缓存背景、复用 typed arrays 和绘制分组减少了部分成本，但不能据此声称 CPU 或电量成本很低。[模拟步骤][world-init]、[渲染][render]、[采样][raster]
- renderer 使用 `getContext("2d", { alpha: false })`，背景填黑并画网格；直接叠在原生卡片上不会得到透明鲨鱼层。示例是整页黑底，不能代表输入框里的效果。[上下文与背景][render]、[示例 HTML][html]
- 引擎在 canvas 离开网页视口时暂停；减少动态效果时先模拟 240 步再画一张静止图。它没有 macOS 窗口隐藏/遮挡接口，`blur` 只清除指针状态。[生命周期][engine]

**建议的首轮观察参数，均未实测：** 只放 1 条鲨鱼，去掉鱼群、捕食、水花、网格和高亮闪烁；尝试 20–30 FPS、约 0.8–1.2 秒退边、停顿 5–8 秒后约 2 秒返回。低亮度、速度和大小需要在真实编辑区调整。这些数字是起点，不是性能、可读性或低干扰效果的保证。

调研能确认结构上可接入，尚不能确认真实窗口里的视觉质量、输入延迟、CPU/耗电或长期使用时的注意力影响。后续若实施，应重点观察连续输入与中文组词不被打断、退边路径不扫过正文、隐藏后停止绘制、窄窗口仍可辨认，以及减少动态效果生效。

[tree]: https://github.com/stackedlol/ascii-sharks/tree/c521e24a787e6d4cc460d4cf2b9815f25e4fe453
[readme]: https://github.com/stackedlol/ascii-sharks/blob/c521e24a787e6d4cc460d4cf2b9815f25e4fe453/README.md
[world-init]: https://github.com/stackedlol/ascii-sharks/blob/c521e24a787e6d4cc460d4cf2b9815f25e4fe453/src/world.ts#L19-L265
[steering]: https://github.com/stackedlol/ascii-sharks/blob/c521e24a787e6d4cc460d4cf2b9815f25e4fe453/src/world.ts#L459-L597
[fish-input]: https://github.com/stackedlol/ascii-sharks/blob/c521e24a787e6d4cc460d4cf2b9815f25e4fe453/src/world.ts#L401-L411
[engine]: https://github.com/stackedlol/ascii-sharks/blob/c521e24a787e6d4cc460d4cf2b9815f25e4fe453/src/engine.ts#L4-L135
[render]: https://github.com/stackedlol/ascii-sharks/blob/c521e24a787e6d4cc460d4cf2b9815f25e4fe453/src/renderer.ts#L269-L423
[raster]: https://github.com/stackedlol/ascii-sharks/blob/c521e24a787e6d4cc460d4cf2b9815f25e4fe453/src/renderer.ts#L638-L812
[package]: https://github.com/stackedlol/ascii-sharks/blob/c521e24a787e6d4cc460d4cf2b9815f25e4fe453/package.json
[react]: https://github.com/stackedlol/ascii-sharks/blob/c521e24a787e6d4cc460d4cf2b9815f25e4fe453/src/react.tsx
[tsconfig]: https://github.com/stackedlol/ascii-sharks/blob/c521e24a787e6d4cc460d4cf2b9815f25e4fe453/tsconfig.json
[html]: https://github.com/stackedlol/ascii-sharks/blob/c521e24a787e6d4cc460d4cf2b9815f25e4fe453/index.html
[exports]: https://github.com/stackedlol/ascii-sharks/blob/c521e24a787e6d4cc460d4cf2b9815f25e4fe453/src/index.ts
[licensing]: https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository
