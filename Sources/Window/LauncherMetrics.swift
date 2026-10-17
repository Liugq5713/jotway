import SwiftUI

/// 启动器界面的尺寸与动效常量。
///
/// 此前所有尺寸内联在使用处（圆角七种、内边距四种），改一处漏一片。
/// 双卡结构落地时一并收敛到这里——输入卡 / 悬浮层的几何关系只看这一个文件。
enum LauncherMetrics {
    /// 面板内容宽度。
    static let panelWidth: CGFloat = 560
    static let stickyWidth: CGFloat = 300
    static let stickyHeight: CGFloat = 200
    static let stickyMinWidth: CGFloat = 240
    static let stickyMinHeight: CGFloat = 160
    /// 输入卡圆角。
    static let inputCardCornerRadius: CGFloat = 14
    /// 悬浮层圆角。
    static let overlayCornerRadius: CGFloat = 12
    /// 输入卡与悬浮层之间的透明间隙（吞点击、不穿透）。
    static let cardGap: CGFloat = 8
    /// 输入卡内边距。
    static let cardPaddingH: CGFloat = 20
    static let cardPaddingTop: CGFloat = 20
    static let cardPaddingBottom: CGFloat = 16
    /// 快捷输入 chrome 保持 70 pt；初始两行编辑区 52 pt，因此卡片最小 122 pt。
    static let inputCardChromeHeight: CGFloat = cardPaddingTop + cardInnerGap + actionRowHeight + cardPaddingBottom
    static let inputCardMinHeight: CGFloat = inputCardChromeHeight + quickInputEditorMinHeight
    /// 输入卡自动长高的上限，超出后编辑器内部滚动。
    static let inputCardMaxHeight: CGFloat = 360
    /// 输入卡内编辑区与动作行之间的间距（与 cardGap 区分：那是卡与选择器卡的间距）。
    static let cardInnerGap: CGFloat = 12
    /// 动作行始终占位；空闲时只隐藏标签。
    static let actionRowHeight: CGFloat = 22
    /// 非空草稿的目标文字按内容收紧，长名称最多占 120 pt。
    static let targetLabelMaxWidth: CGFloat = 120
    /// 显式标记 5 + 图标 12 + 分隔 1 + Return 16 + 四处间距 20 + 水平内边距。
    static let targetAccessoryWidth: CGFloat = 5 + 12 + 1 + 16 + 4 * 5 + 2 * targetPaddingH
    static let targetPaddingH: CGFloat = 7
    static let editorFontSize: CGFloat = 16
    /// 普通中英文基线间距；用额外行距实现，保留字形与光标的自然行框。
    static let editorLineHeight: CGFloat = 26
    /// 原生测量及便签继续使用单行基础值。
    static let editorMinHeight: CGFloat = editorLineHeight
    static let quickInputEditorMinHeight: CGFloat = 2 * editorLineHeight
    /// 编辑区上限 290；超出后内部滚动，动作行始终可见。
    static let editorMaxHeight: CGFloat = inputCardMaxHeight - inputCardChromeHeight
    /// 悬浮层结果行高。
    static let overlayRowHeight: CGFloat = 38
    /// 悬浮层列表最多直接展示的行数，超出转滚动。
    static let overlayMaxRows = 6
    /// 模板双行候选独立于其他结果行；标题、说明与内边距不进入滚动区。
    static let templateRowHeight: CGFloat = 52
    static let templateHeaderHeight: CGFloat = 28
    static let templateFooterHeight: CGFloat = 28
    static let templateMenuPadding: CGFloat = 6
    static var templateMenuChromeHeight: CGFloat {
        templateHeaderHeight + templateFooterHeight + 2 * templateMenuPadding
    }
    static func templateListHeight(candidateCount: Int, availableHeight: CGFloat) -> CGFloat {
        min(CGFloat(max(0, min(candidateCount, overlayMaxRows))) * templateRowHeight,
            max(0, availableHeight - templateMenuChromeHeight))
    }
    /// 悬浮层淡入时长（纯透明度，无位移；窗口改高瞬时完成，不做动画）。
    static let overlayAppearDuration: Double = 0.10
    /// Reduce Motion 下统一降到的时长，与面板进出动画一致。
    static let reducedMotionDuration: Double = 0.08
}
