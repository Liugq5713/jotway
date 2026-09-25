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
    static let cardPaddingH: CGFloat = 20
    static let cardPaddingTop: CGFloat = 18
    static let cardPaddingBottom: CGFloat = 14
    /// 输入卡最小高，与窗口初始尺寸共用：18 + 26 + 10 + 22 + 14 = 90。
    static let inputCardMinHeight: CGFloat = cardPaddingTop + editorMinHeight + cardInnerGap + actionRowHeight + cardPaddingBottom
    /// 输入卡自动长高的上限，超出后编辑器内部滚动。
    static let inputCardMaxHeight: CGFloat = 360
    /// 输入卡内编辑区与动作行之间的间距（与 cardGap 区分：那是卡与选择器卡的间距）。
    static let cardInnerGap: CGFloat = 10
    /// 动作行始终占位；空闲时只隐藏标签。
    static let actionRowHeight: CGFloat = 22
    static let editorFontSize: CGFloat = 16
    /// 普通中英文基线间距；用额外行距实现，保留字形与光标的自然行框。
    static let editorLineHeight: CGFloat = 26
    static let editorMinHeight: CGFloat = editorLineHeight
    /// 编辑区上限 296；超出后内部滚动，动作行始终可见。
    static let editorMaxHeight: CGFloat = inputCardMaxHeight - cardPaddingTop - cardPaddingBottom - cardInnerGap - actionRowHeight
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
