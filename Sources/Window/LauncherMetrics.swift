import SwiftUI

/// 启动器界面的尺寸与动效常量（launcher-ui.md §3、§6 P2）。
///
/// 此前所有尺寸内联在使用处（圆角七种、内边距四种），改一处漏一片。
/// 双卡结构落地时一并收敛到这里——输入卡 / 悬浮层的几何关系只看这一个文件。
enum LauncherMetrics {
    /// 面板内容宽度。
    static let panelWidth: CGFloat = 560
    /// 输入卡圆角。
    static let inputCardCornerRadius: CGFloat = 14
    /// 悬浮层圆角。
    static let overlayCornerRadius: CGFloat = 12
    /// 输入卡与悬浮层之间的透明间隙（吞点击、不穿透）。
    static let cardGap: CGFloat = 8
    /// 输入卡内边距。
    static let cardPaddingH: CGFloat = 16
    static let cardPaddingV: CGFloat = 14
    /// 输入卡最小高（D2 固定双行：14 + 24 编辑区 + 8 卡内间距 + 28 动作行 + 14）。
    static let inputCardMinHeight: CGFloat = 88
    /// 输入卡自动长高的上限，超出后编辑器内部滚动。
    static let inputCardMaxHeight: CGFloat = 360
    /// 输入卡内编辑区与动作行之间的间距（与 cardGap 区分：那是卡与选择器卡的间距）。
    static let cardInnerGap: CGFloat = 8
    /// 动作行固定高度（28pt，始终占位；空闲时留白但保留容器）。
    static let actionRowHeight: CGFloat = 28
    /// 编辑区最小高度（单行正文 17pt + 上下缓冲）。
    static let editorMinHeight: CGFloat = 24
    /// 多行正文额外行距；字号不变，只让连续内容更易扫读。
    static let editorLineSpacing: CGFloat = 2
    /// 编辑区自动长高的上限（= 卡上限 360 - 14*2 - 8 - 28），超出内部滚动，动作行始终可见。
    static let editorMaxHeight: CGFloat = 296
    /// 悬浮层结果行高。
    static let overlayRowHeight: CGFloat = 38
    /// 悬浮层列表最多直接展示的行数，超出转滚动。
    static let overlayMaxRows = 6
    /// 悬浮层淡入时长（纯透明度，无位移；窗口改高瞬时完成，不做动画）。
    static let overlayAppearDuration: Double = 0.10
    /// 悬浮层淡出时长。
    static let overlayDisappearDuration: Double = 0.08
    /// Reduce Motion 下统一降到的时长，与面板进出动画一致。
    static let reducedMotionDuration: Double = 0.08
}
