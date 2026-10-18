import AppKit
import CoreText
import KeyboardShortcuts
import SwiftUI

/// AppKit 编辑器与窗口之间的焦点、组词和用户事件桥接。
@MainActor @Observable
final class EditorFocusTarget {
    enum TargetMenuItem: Equatable {
        case target(String)
        case automatic
    }

    @ObservationIgnored weak var textView: NSTextView?
    @ObservationIgnored weak var modeButton: NSButton?
    @ObservationIgnored var recentDocumentButtons: [NSButton] = []
    @ObservationIgnored var recentDocumentCommandButtons: [Int: NSButton] = [:]
    @ObservationIgnored var reviewButtons: [NSButton] = []
    @ObservationIgnored weak var thinkingButton: NSButton?
    @ObservationIgnored var thinkingCommandButtons: [Int: NSButton] = [:]
    @ObservationIgnored var preserveSelectionOnNextFocus = false
    var targetSelectorFocusRequest = 0
    var highlightedTargetMenuItem: TargetMenuItem?
    var highlightedTemplateID: String?

    func refreshTemplateFocus(previous: [InputTemplate], candidates: [InputTemplate]) {
        if previous.isEmpty || !candidates.contains(where: { $0.id == highlightedTemplateID }) {
            highlightedTemplateID = candidates.first?.id
        }
    }

    func moveTemplateFocus(forward: Bool, state: LauncherViewState) {
        let candidates = state.templateCandidates
        guard !candidates.isEmpty else { return }
        let index = candidates.firstIndex(where: { $0.id == highlightedTemplateID }) ?? 0
        highlightedTemplateID = candidates[(index + (forward ? 1 : -1) + candidates.count) % candidates.count].id
    }

    func selectHighlightedTemplate(state: LauncherViewState, send: (LauncherEvent) -> Void) {
        guard state.isTemplateMenuVisible, !state.isComposingText,
              textView?.hasMarkedText() != true else { return }
        guard let candidate = state.templateCandidates.first(where: { $0.id == highlightedTemplateID })
            ?? state.templateCandidates.first else { return }
        send(.selectTemplate(candidate))
        restoreEditorFocus()
    }

    func resetTargetMenuFocus(state: LauncherViewState) {
        highlightedTargetMenuItem = state.intentCandidates.first(where: \.isSelected)
            .map { .target($0.id) } ?? state.intentCandidates.first.map { .target($0.id) }
            ?? (state.hasExplicitTarget ? .automatic : nil)
    }

    func moveTargetMenuFocus(forward: Bool, state: LauncherViewState) {
        let items = targetMenuItems(state: state)
        guard !items.isEmpty else { return }
        if highlightedTargetMenuItem == nil { resetTargetMenuFocus(state: state) }
        let index = highlightedTargetMenuItem.flatMap { items.firstIndex(of: $0) }
            ?? (forward ? -1 : 0)
        highlightedTargetMenuItem = items[(index + (forward ? 1 : -1) + items.count) % items.count]
    }

    func selectHighlightedTarget(state: LauncherViewState, send: (LauncherEvent) -> Void) {
        guard state.isIntentCandidateMenuVisible, !state.isComposingText,
              textView?.hasMarkedText() != true else { return }
        if !targetMenuItems(state: state).contains(where: { $0 == highlightedTargetMenuItem }) {
            resetTargetMenuFocus(state: state)
        }
        switch highlightedTargetMenuItem {
        case .target(let id): send(.selectTarget(id, trigger: .keyboard))
        case .automatic: send(.useAutomatic(trigger: .keyboard))
        case nil: break
        }
        send(.candidateMenuChanged(false))
        restoreEditorFocus()
    }

    func restoreEditorFocus() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
    }

    func focusModeControl() {
        guard textView?.hasMarkedText() != true, let modeButton else { return }
        modeButton.window?.makeFirstResponder(modeButton)
    }

    @discardableResult
    func focusRecentDocument(last: Bool = false) -> Bool {
        guard textView?.hasMarkedText() != true else { return false }
        let enabled = recentDocumentButtons.filter { $0.isEnabled && !$0.isHiddenOrHasHiddenAncestor && $0.window != nil }
        guard let button = last ? enabled.last : enabled.first else { return false }
        return button.window?.makeFirstResponder(button) == true
    }

    @discardableResult
    func focusReview(last: Bool = false) -> Bool {
        guard textView?.hasMarkedText() != true else { return false }
        let enabled = reviewButtons.filter { $0.isEnabled && $0.window != nil }
        guard let button = last ? enabled.last : enabled.first else { return false }
        return button.window?.makeFirstResponder(button) == true
    }

    func restoreEditorIfRecentDocumentFocused() {
        guard textView?.hasMarkedText() != true, let responder = textView?.window?.firstResponder else { return }
        if recentDocumentButtons.contains(where: { $0 === responder })
            || recentDocumentCommandButtons.values.contains(where: { $0 === responder }) { restoreEditorFocus() }
    }

    func focusFollowingRecentDocument() {
        if !focusReview(), !focusThinkingPrompt() { restoreEditorFocus() }
    }

    @discardableResult
    func moveRecentDocumentCommandFocus(from slot: Int, forward: Bool, state: LauncherViewState) -> Bool {
        guard textView?.hasMarkedText() != true, !state.isComposingText else { return false }
        let slots = state.selectedRecentDocument != nil
            ? recentDocumentCommandButtons.keys.sorted().filter {
                guard let button = recentDocumentCommandButtons[$0] else { return false }
                return button.isEnabled && !button.isHiddenOrHasHiddenAncestor && button.window != nil
            } : []
        let next = forward ? slots.first(where: { $0 > slot }) : slots.last(where: { $0 < slot })
        if let next, let button = recentDocumentCommandButtons[next] {
            return button.window?.makeFirstResponder(button) == true
        }
        if forward { focusFollowingRecentDocument() }
        else if !focusRecentDocument() { restoreEditorFocus() }
        return false
    }

    @discardableResult
    func focusThinkingPrompt() -> Bool {
        guard textView?.hasMarkedText() != true, let thinkingButton, thinkingButton.isEnabled else { return false }
        return thinkingButton.window?.makeFirstResponder(thinkingButton) == true
    }

    func moveThinkingCommandFocus(from slot: Int, forward: Bool, state: LauncherViewState) {
        let slots = state.thinkingPrompt?.display.isOpen == true
            ? thinkingCommandButtons.keys.sorted().filter { thinkingCommandButtons[$0]?.isEnabled == true
                && thinkingCommandButtons[$0]?.window != nil } : []
        let next = forward ? slots.first(where: { $0 > slot }) : slots.last(where: { $0 < slot })
        if let next, let button = thinkingCommandButtons[next] { button.window?.makeFirstResponder(button) }
        else if !forward { if !focusThinkingPrompt() { restoreEditorFocus() } }
        else if state.mode == .quickInput, state.canChooseTarget { targetSelectorFocusRequest += 1 }
        else { restoreEditorFocus() }
    }

    private func targetMenuItems(state: LauncherViewState) -> [TargetMenuItem] {
        state.intentCandidates.map { .target($0.id) } + (state.hasExplicitTarget ? [.automatic] : [])
    }
}

/// 记录面板的编辑器：唤起即空白卡片，直奔输入。
/// 默认 Enter 提交、Shift+Enter 换行；Esc 暂存并关闭。
/// SwiftUI TextEditor 在非激活面板内焦点/按键不可靠，按文档预案回退为
/// NSViewRepresentable 包 NSTextView（顺带解决 IME 组词中回车误触保存的问题）。
private struct LauncherHeightMeasurement: Equatable {
    let height: CGFloat
    let generation: UUID
}

private struct LauncherTotalHeightKey: PreferenceKey {
    static let defaultValue: LauncherHeightMeasurement? = nil
    static func reduce(value: inout LauncherHeightMeasurement?, nextValue: () -> LauncherHeightMeasurement?) {
        if let next = nextValue() { value = next }
    }
}

private struct LauncherInputCardHeightKey: PreferenceKey {
    static let defaultValue: LauncherHeightMeasurement? = nil
    static func reduce(value: inout LauncherHeightMeasurement?, nextValue: () -> LauncherHeightMeasurement?) {
        if let next = nextValue() { value = next }
    }
}

private struct TemplateMenuScrollTarget: Equatable {
    let candidates: [InputTemplate]
    let highlightedID: String?
    let height: CGFloat
}

private struct TargetMenuScrollTarget: Equatable {
    let candidates: [IntentCandidate]
    let highlightedID: String?
    let height: CGFloat
}

struct EditorView: View {
    @Binding var text: String
    var appState: AppState? = nil
    @Environment(\.openSettings) private var openSettings
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let focusTarget: EditorFocusTarget
    let state: LauncherViewState
    let send: (LauncherEvent) -> Void
    /// 内容尺寸变化上报（总高、输入卡高），窗口据此顶锚定改高
    var onContentSizeChange: (CGFloat, CGFloat, UUID) -> Void = { _, _, _ in }
    /// 手动调整时固定输入卡高度，新增空间交给编辑区；nil 恢复按正文自动长高。
    var manualInputCardHeight: CGFloat? = nil
    var maximumContentHeight: CGFloat = 668

    /// placeholder 单点定义（EditorTextView 的默认值也引用这里）。
    static var placeholderText: String { L10n.text("launcher.placeholder") }

    @State private var actionRowWidth: CGFloat = LauncherMetrics.panelWidth - 2 * LauncherMetrics.cardPaddingH
    @State private var isInputCardHovered = false
    @State private var editorTextHeight: CGFloat = LauncherMetrics.editorMinHeight
    @State private var reportedTotalHeight: LauncherHeightMeasurement?
    @State private var reportedCardHeight: LauncherHeightMeasurement?
    /// 同一轮布局里总高与卡高两个 preference 会先后到达，合并为一次上报，避免窗口收两帧几何。
    @State private var geometryReportScheduled = false
    @FocusState private var isTargetSelectorFocused: Bool

    var body: some View {
        let generation = state.modeGeneration
        // 菜单开合与 NSPanel 的瞬时改高保持一致；整栈动画会让正文先跳位再滑回。
        let stack = VStack(spacing: LauncherMetrics.cardGap) {
            inputCard
            if isOverlayVisible {
                overlayCard
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: LauncherTotalHeightKey.self,
                                       value: .init(height: proxy.size.height, generation: generation))
            }
        )
        .onPreferenceChange(LauncherTotalHeightKey.self) { total in
            reportedTotalHeight = total
            scheduleGeometryReport()
        }
        .onPreferenceChange(LauncherInputCardHeightKey.self) { card in
            reportedCardHeight = card
            scheduleGeometryReport()
        }
        // 宿主尚未改高时也接受较小高度，让超出内容向下延展，避免临时居中跳位。
        stack
            .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
            .onChange(of: state.isIntentCandidateMenuVisible) { _, visible in
                if visible {
                    if focusTarget.highlightedTargetMenuItem == nil { focusTarget.resetTargetMenuFocus(state: state) }
                } else {
                    focusTarget.highlightedTargetMenuItem = nil
                }
            }
            .onChange(of: focusTarget.targetSelectorFocusRequest) { _, _ in
                if hasDraftContent, state.canChooseTarget { isTargetSelectorFocused = true }
            }
            .onChange(of: state.templateCandidates) { previous, candidates in
                focusTarget.refreshTemplateFocus(previous: previous, candidates: candidates)
            }
    }

    /// 合并同一轮布局里的几何上报：总高与卡高到齐后只通知窗口一次。
    private func scheduleGeometryReport() {
        guard !geometryReportScheduled else { return }
        geometryReportScheduled = true
        DispatchQueue.main.async {
            geometryReportScheduled = false
            let generation = state.modeGeneration
            guard let total = reportedTotalHeight, let card = reportedCardHeight,
                  total.generation == generation, card.generation == generation else { return }
            onContentSizeChange(total.height, card.height, generation)
        }
    }

    /// 悬浮层显示目标选择器、@ 补全菜单或所选 action 的内容。
    private var isOverlayVisible: Bool {
        if state.isReadingGettingStarted { return false }
        if state.selectedRecentDocument != nil || state.thinkingPrompt?.display.isOpen == true { return true }
        if state.mode == .sticky { return false }
        return state.isIntentCandidateMenuVisible || state.isTemplateMenuVisible
            || state.showsCodexRecentTasks || state.clipboardHistory != nil || state.showsReview
    }

    private var accent: Color {
        Color(nsColor: EditorPalette.accent)
    }

    /// 每张卡独立裁剪材质；辅助设置仅更新背景，不重建原生编辑器。
    private func cardChrome<Content: View>(_ content: Content, cornerRadius: CGFloat,
                                         onBackgroundClick: (() -> Void)? = nil) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        // 圆角之外保持透明；柔和的"浮起"感来自窗口的系统阴影（RecordPanel.hasShadow）。
        return content
            .background(WindowDragHandle(onClick: onBackgroundClick)) // 拖拽只挂在非文本区域。
            .background {
                EditorCardBackground(cornerRadius: cornerRadius, colorScheme: colorScheme,
                                     reduceTransparency: reduceTransparency,
                                     increasesContrast: colorSchemeContrast == .increased)
            }
            .overlay { cardOutline(shape) }
    }

    private func cardOutline(_ shape: RoundedRectangle) -> some View {
        shape
            .strokeBorder(
                colorSchemeContrast == .increased ? Color.primary.opacity(0.70) : Color(nsColor: EditorPalette.outline),
                lineWidth: colorSchemeContrast == .increased ? 1.5 : 1
            )
            .allowsHitTesting(false)
    }

    private var inputCardChromeHeight: CGFloat {
        LauncherMetrics.inputCardChromeHeight
    }

    /// Reserve the lower area's smallest useful viewport before reducing the writing preference.
    /// On very small screens the old one-line budget gives way only after the lower rows shrink.
    private func reservedOverlayHeight(for maximumHeight: CGFloat) -> CGFloat {
        guard isOverlayVisible else { return 0 }
        let desired = state.isTemplateMenuVisible
            ? LauncherMetrics.templateMenuChromeHeight + LauncherMetrics.templateRowHeight : 64
        let floor = state.isTemplateMenuVisible ? LauncherMetrics.templateMenuChromeHeight : 64
        let afterOneLine = maximumHeight - LauncherMetrics.inputCardChromeHeight
            - LauncherMetrics.editorMinHeight - LauncherMetrics.cardGap
        return min(max(floor, min(desired, afterOneLine)),
                   max(0, maximumHeight - LauncherMetrics.inputCardChromeHeight - LauncherMetrics.cardGap))
    }

    private func maximumInputCardHeight(for maximumHeight: CGFloat) -> CGFloat {
        max(0, maximumHeight - (isOverlayVisible ? LauncherMetrics.cardGap + reservedOverlayHeight(for: maximumHeight) : 0))
    }

    /// RecordPanel uses this same effective minimum when constraining its window and manual height.
    func minimumInputCardHeight(for maximumHeight: CGFloat) -> CGFloat {
        min(state.mode == .sticky ? LauncherMetrics.stickyMinHeight : LauncherMetrics.inputCardMinHeight,
            maximumInputCardHeight(for: maximumHeight))
    }

    var minimumInputCardHeight: CGFloat { minimumInputCardHeight(for: maximumContentHeight) }

    private var editorMinimumHeight: CGFloat {
        let preferred = state.mode == .sticky ? LauncherMetrics.editorMinHeight : LauncherMetrics.quickInputEditorMinHeight
        return max(0, min(preferred, minimumInputCardHeight - inputCardChromeHeight))
    }

    private var editorMaximumHeight: CGFloat {
        min(LauncherMetrics.editorMaxHeight,
            max(0, maximumInputCardHeight(for: maximumContentHeight) - inputCardChromeHeight))
    }

    private var editorHeight: CGFloat {
        min(max(editorTextHeight, editorMinimumHeight), editorMaximumHeight)
    }

    private var overlayAvailableHeight: CGFloat {
        let cardHeight = min(max(reportedCardHeight?.height ?? 0, minimumInputCardHeight),
                             maximumInputCardHeight(for: maximumContentHeight))
        return max(0, maximumContentHeight - cardHeight - LauncherMetrics.cardGap)
    }

    private var inputCard: some View {
        let generation = state.modeGeneration
        return cardChrome(
            VStack(spacing: LauncherMetrics.cardInnerGap) {
                EditorTextViewRepresentable(
                    text: $text,
                    focusTarget: focusTarget,
                    state: state,
                    send: send,
                    placeholder: Self.placeholderText,
                    automaticViewportHeightLimit: state.mode == .quickInput && manualInputCardHeight == nil
                        ? editorMaximumHeight : nil,
                    onContentHeightChange: { editorTextHeight = $0 }
                )
                .frame(minHeight: manualInputCardHeight == nil ? editorHeight : editorMinimumHeight,
                       maxHeight: manualInputCardHeight == nil ? editorHeight : .infinity)
                actionRow
            }
            .padding(.horizontal, LauncherMetrics.cardPaddingH)
            .padding(.top, LauncherMetrics.cardPaddingTop)
            .padding(.bottom, LauncherMetrics.cardPaddingBottom)
            .frame(height: manualInputCardHeight.map {
                max(min($0, maximumInputCardHeight(for: maximumContentHeight)), minimumInputCardHeight)
            })
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: LauncherInputCardHeightKey.self,
                                           value: .init(height: proxy.size.height, generation: generation))
                }
            ),
            cornerRadius: LauncherMetrics.inputCardCornerRadius,
            onBackgroundClick: {
                guard let textView = focusTarget.textView else { return }
                textView.window?.makeFirstResponder(textView)
            }
        )
        .onHover { isInputCardHovered = $0 }
    }

    // MARK: - 动作行（固定 22pt，始终占位）

    /// 模式入口固定左下；快捷输入的反馈与目标占用其右侧剩余空间。
    private var actionRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ModeControl(focusTarget: focusTarget, state: state, send: send,
                        isCardHovered: isInputCardHovered,
                        increasesContrast: colorSchemeContrast == .increased)
                .frame(width: 22, height: 22)
                .frame(height: LauncherMetrics.actionRowHeight)
            if state.canShowRecentDocuments {
                RecentDocumentControls(focusTarget: focusTarget, state: state,
                                       isCardHovered: isInputCardHovered,
                                       increasesContrast: colorSchemeContrast == .increased, send: send)
                    .frame(width: 22, height: 22)
                    .frame(height: LauncherMetrics.actionRowHeight)
            }
            if state.mode == .quickInput {
                NotesReviewControls(focusTarget: focusTarget, state: state, send: send,
                                    isCardHovered: isInputCardHovered,
                                    increasesContrast: colorSchemeContrast == .increased)
                    .frame(width: 22, height: 22)
                    .fixedSize()
            }
            if hasDraftContent {
                DraftThinkingPromptControl(focusTarget: focusTarget, state: state,
                    isCardHovered: isInputCardHovered,
                    increasesContrast: colorSchemeContrast == .increased, send: send)
                    .frame(width: 22, height: 22)
            }
            if state.mode == .quickInput {
                HStack(alignment: .bottom, spacing: 8) {
                    if hasDraftContent, !state.isReadingGettingStarted {
                        ActionPlanResultRow(state: state)
                    } else {
                        Spacer(minLength: 0)
                    }
                    actionTarget
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { actionRowWidth = $0 }
            } else {
                Spacer(minLength: 0)
            }
        }
        // 下端对齐：动作标签贴着动作行下缘，视觉更沉稳。
        .frame(height: LauncherMetrics.actionRowHeight, alignment: .bottom)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hasDraftContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private var actionTarget: some View {
        if hasDraftContent, !state.isReadingGettingStarted {
            if state.isTemplateMenuVisible {
                returnHint
                    .padding(.horizontal, LauncherMetrics.targetPaddingH)
                    .frame(height: LauncherMetrics.actionRowHeight)
                    .layoutPriority(1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("launcher-confirm-hint")
                    .accessibilityLabel(state.displayedActionTitle ?? L10n.text("launcher.choose_target"))
                    .accessibilityHint(actionReturnHelp)
                    .help((state.displayedActionTitle.map { $0 + "\n" } ?? "")
                        + actionReturnHelp)
            } else {
                targetSelector
                    .layoutPriority(1)
            }
        }
    }

    private var returnHint: some View {
        Image(systemName: "return")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(colorSchemeContrast == .increased ? Color.secondary : Color(nsColor: EditorPalette.buttonText))
            .frame(width: 16, height: 16, alignment: .center)
    }

    private var actionReturnHelp: String {
        L10n.text(state.isTemplateMenuVisible ? "templates.insert_help" : "launcher.confirm_action_help")
    }

    @ViewBuilder
    private var explicitTargetMark: some View {
        if hasDraftContent || state.hasExplicitTarget {
            Circle().fill(accent).frame(width: 5, height: 5)
                .opacity(state.hasExplicitTarget ? 1 : 0)
                .accessibilityHidden(true)
        }
    }

    /// Pointer confirmation and keyboard target selection share the existing capsule.
    private var targetSelector: some View {
        HStack(spacing: 5) {
            explicitTargetMark
            Image(systemName: state.displayedActionIcon ?? "square.grid.2x2")
                .font(.system(size: 12))
                .frame(width: 12, height: 12)
                .accessibilityHidden(true)
            Text(state.displayedActionTitle ?? L10n.text("launcher.choose_target"))
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: hasDraftContent ? min(LauncherMetrics.targetLabelMaxWidth,
                    max(0, actionRowWidth - LauncherMetrics.targetAccessoryWidth)) : nil, alignment: .leading)
                .frame(maxWidth: hasDraftContent ? nil : 260, alignment: .leading)
            if hasDraftContent {
                Rectangle().fill(Color(nsColor: EditorPalette.buttonText).opacity(0.25))
                    .frame(width: 1, height: 10)
                    .accessibilityHidden(true)
                returnHint
                    .opacity(state.displayedActionTitle == nil ? 0 : 1)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, LauncherMetrics.targetPaddingH)
        .frame(height: LauncherMetrics.actionRowHeight)
        .background {
            Capsule().fill(Color(nsColor: state.isIntentCandidateMenuVisible
                ? EditorPalette.buttonActive : EditorPalette.button))
        }
        .overlay {
            TargetCapsulePointer(focusTarget: focusTarget, state: state, activate: confirmTargetWithPointer)
                .accessibilityHidden(true)
        }
        .overlay {
            if isTargetSelectorFocused {
                Capsule().strokeBorder(colorSchemeContrast == .increased ? Color.primary : accent, lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
        }
        .focusable(state.canChooseTarget)
        .focused($isTargetSelectorFocused)
        .focusEffectDisabled()
        .fixedSize(horizontal: true, vertical: false)
        .foregroundStyle(colorSchemeContrast == .increased ? Color.primary : Color(nsColor: EditorPalette.buttonText))
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("launcher-choose-target")
        .accessibilityLabel(L10n.text("launcher.choose_target"))
        .accessibilityValue(targetSelectorValue)
        .accessibilityHint(L10n.text("launcher.choose_target_help"))
        .accessibilityAction(named: Text(L10n.text("launcher.confirm_target")), confirmTargetWithPointer)
        .help(targetSelectorValue + "\n" + L10n.text("launcher.choose_target_help"))
        .onKeyPress(keys: [.return, .space, .upArrow, .downArrow, .escape, .tab], phases: .down) { key in
            handleTargetSelectorKey(key)
        }
    }

    private var targetSelectorValue: String {
        let mode = L10n.text(state.hasExplicitTarget ? "launcher.target_explicit" : "launcher.target_automatic")
        return state.displayedActionTitle.map { "\($0), \(mode)" } ?? mode
    }

    private func confirmTargetWithPointer() {
        TargetCapsulePointer.activate(focusTarget: focusTarget, state: state, send: send) {
            isTargetSelectorFocused = false
        }
    }

    private func handleTargetSelectorKey(_ key: KeyPress) -> KeyPress.Result {
        guard state.canChooseTarget, focusTarget.textView?.hasMarkedText() != true,
              !state.isComposingText else { return .ignored }
        if key.modifiers == .option, key.key == .upArrow || key.key == .downArrow {
            if state.intentCanCycle { send(.cycleTarget(forward: key.key == .downArrow)) }
            return .handled
        }
        if key.key == .escape {
            send(.candidateMenuChanged(false))
            isTargetSelectorFocused = false
            focusTarget.restoreEditorFocus()
            return .handled
        }
        if state.isIntentCandidateMenuVisible {
            if key.key == .upArrow || key.key == .downArrow || key.key == .tab {
                let forward = key.key == .downArrow || (key.key == .tab && !key.modifiers.contains(.shift))
                focusTarget.moveTargetMenuFocus(forward: forward, state: state)
            } else if key.key == .return || key.key == .space {
                focusTarget.selectHighlightedTarget(state: state, send: send)
                isTargetSelectorFocused = false
            }
            return .handled
        }
        if key.key == .tab {
            isTargetSelectorFocused = false
            if key.modifiers.contains(.shift) { focusTarget.moveThinkingCommandFocus(from: 3, forward: false, state: state) }
            else { focusTarget.focusModeControl() }
            return .handled
        }
        if key.key == .return || key.key == .space || key.key == .upArrow || key.key == .downArrow {
            send(.toggleTargetMenu)
            if state.isIntentCandidateMenuVisible { focusTarget.resetTargetMenuFocus(state: state) }
            return .handled
        }
        return .ignored
    }

    private var overlayCard: some View {
        cardChrome(Group {
            if let document = state.selectedRecentDocument {
                RecentDocumentDetailView(document: document, state: state, focusTarget: focusTarget, send: send,
                    text: state.recentDocumentText, error: state.recentDocumentError,
                    isLoading: state.isLoadingRecentDocument,
                    maximumHeight: overlayAvailableHeight,
                    composing: state.isComposingText,
                    canInteract: { focusTarget.textView?.hasMarkedText() != true },
                    retry: { send(.retryRecentDocument) },
                    close: { send(.closeRecentDocument); focusTarget.restoreEditorFocus() })
            } else if let prompt = state.thinkingPrompt, prompt.display.isOpen {
                DraftThinkingPromptView(prompt: prompt, focusTarget: focusTarget, state: state,
                    maximumHeight: overlayAvailableHeight, send: send, configure: {
                        appState?.settingsDestination = .ai
                        openSettings()
                    })
            } else if state.showsReview {
                NotesReviewView(
                    period: state.reviewPeriod,
                    summary: state.reviewSummary,
                    preview: state.reviewPreview,
                    requestMetadata: state.reviewRequestMetadata,
                    isLoading: state.isLoadingReview,
                    failed: state.reviewFailed,
                    coverageIncomplete: state.reviewCoverageIncomplete,
                    unavailableReason: state.reviewUnavailableReason,
                    maximumHeight: overlayAvailableHeight,
                    selectPeriod: { period in
                        guard focusTarget.textView?.hasMarkedText() != true,
                              period != state.reviewPeriod else { return }
                        send(.toggleReview(period))
                        focusTarget.restoreEditorFocus()
                    },
                    close: { send(.closeReview); focusTarget.restoreEditorFocus() })
            } else if let history = state.clipboardHistory, !state.isIntentCandidateMenuVisible, !state.isTemplateMenuVisible {
                ClipboardHistoryView(history: history,
                    height: min(300, overlayAvailableHeight),
                    composing: state.isComposingText,
                    select: { id in
                        guard focusTarget.textView?.hasMarkedText() != true else { return }
                        send(.clipboardSelect(id)); focusTarget.restoreEditorFocus()
                    })
            } else if state.showsCodexRecentTasks, !state.isIntentCandidateMenuVisible, !state.isTemplateMenuVisible {
                CodexRecentTasksView(
                    maximumHeight: overlayAvailableHeight,
                    composing: state.isComposingText,
                    canOpen: { focusTarget.textView?.hasMarkedText() != true },
                    onOpened: { send(.codexRecentTaskOpened) })
            } else {
                overlayMenuContent
            }
        }, cornerRadius: LauncherMetrics.overlayCornerRadius)
    }

    @ViewBuilder private var overlayMenuContent: some View {
        if state.isTemplateMenuVisible { templateMenuContent }
        else {
            ViewThatFits(in: .vertical) {
                intentCandidateMenuContent
                ScrollViewReader { proxy in
                    ScrollView(.vertical) { intentCandidateMenuContent }
                        .frame(height: overlayAvailableHeight)
                        .task(id: TargetMenuScrollTarget(candidates: state.intentCandidates,
                                                        highlightedID: highlightedTargetScrollID,
                                                        height: overlayAvailableHeight)) {
                            await Task.yield()
                            guard !Task.isCancelled, let id = highlightedTargetScrollID else { return }
                            proxy.scrollTo(id)
                        }
                }
            }
            .frame(maxHeight: overlayAvailableHeight)
        }
    }

    private var templateMenuAvailableHeight: CGFloat { overlayAvailableHeight }

    private var templateMenuContent: some View {
        let highlightedID = state.templateCandidates.contains { $0.id == focusTarget.highlightedTemplateID }
            ? focusTarget.highlightedTemplateID : state.templateCandidates.first?.id
        let listHeight = LauncherMetrics.templateListHeight(candidateCount: state.templateCandidates.count,
                                                           availableHeight: templateMenuAvailableHeight)
        return VStack(alignment: .leading, spacing: 0) {
            Label(L10n.text("templates.menu_title"), systemImage: "text.badge.plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .frame(height: LauncherMetrics.templateHeaderHeight)
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        ForEach(state.templateCandidates) { candidate in
                            templateRow(candidate, highlighted: highlightedID == candidate.id)
                                .id(candidate.id)
                        }
                    }
                }
                .frame(height: listHeight)
                .task(id: TemplateMenuScrollTarget(candidates: state.templateCandidates,
                                                  highlightedID: highlightedID, height: listHeight)) {
                    // Wait for the refreshed rows and viewport to participate in layout.
                    await Task.yield()
                    guard !Task.isCancelled, let highlightedID else { return }
                    proxy.scrollTo(highlightedID)
                }
            }
            templateKeyboardHints
        }
        .padding(LauncherMetrics.templateMenuPadding)
    }

    private func templateRow(_ candidate: InputTemplate, highlighted: Bool) -> some View {
        let preview = candidate.preview
        return Button {
            guard !state.isComposingText, focusTarget.textView?.hasMarkedText() != true else { return }
            send(.selectTemplate(candidate))
            focusTarget.restoreEditorFocus()
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(candidate.name).font(.system(size: 13, weight: .medium))
                    Text(preview).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "return")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 16)
                    .opacity(highlighted ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
            .frame(height: LauncherMetrics.templateRowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(highlighted ? accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { if $0 { focusTarget.highlightedTemplateID = candidate.id } }
        .accessibilityIdentifier("launcher-template-\(candidate.id)")
        .accessibilityLabel(candidate.name + ", " + preview)
        .accessibilityValue(highlighted ? L10n.text("templates.selected") : "")
        .help(candidate.name + "\n" + preview + "\n" + L10n.text("templates.insert_help"))
    }

    private var templateKeyboardHints: some View {
        HStack {
            Spacer(minLength: 8)
            keyHint("↑↓", systemImage: "arrow.up.arrow.down", L10n.text("launcher.navigate"))
            keyHint("⏎", systemImage: "return", L10n.text("templates.insert"))
            keyHint("esc", systemImage: "escape", L10n.text("launcher.collapse"))
        }
        .padding(.horizontal, 10)
        .frame(height: LauncherMetrics.templateFooterHeight)
    }

    private var highlightedTargetScrollID: String? {
        switch focusTarget.highlightedTargetMenuItem {
        case .target(let id): "target." + id
        case .automatic: "automatic"
        case nil: nil
        }
    }

    /// 菜单高亮只属于键盘导航；确定后才改变草稿的路由模式。
    private var intentCandidateMenuContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(state.intentCandidates) { candidate in
                Button {
                    guard focusTarget.textView?.hasMarkedText() != true else { return }
                    send(.selectTarget(candidate.id))
                    send(.candidateMenuChanged(false))
                    isTargetSelectorFocused = false
                    focusTarget.restoreEditorFocus()
                } label: {
                    targetMenuLabel(title: candidate.title, selected: candidate.isSelected,
                                    highlighted: focusTarget.highlightedTargetMenuItem == .target(candidate.id))
                }
                .buttonStyle(.plain)
                .id("target." + candidate.id)
                .accessibilityIdentifier("launcher-target-\(candidate.id)")
                .accessibilityLabel(L10n.text("launcher.switch_target", candidate.title))
                .accessibilityValue(candidate.isSelected ? L10n.text("launcher.target_selected") : "")
            }
            Divider().padding(.horizontal, 10).padding(.vertical, 4)
            Button {
                guard focusTarget.textView?.hasMarkedText() != true else { return }
                send(.useAutomatic())
                isTargetSelectorFocused = false
                focusTarget.restoreEditorFocus()
            } label: {
                targetMenuLabel(title: L10n.text("launcher.use_automatic"), selected: !state.hasExplicitTarget,
                                highlighted: focusTarget.highlightedTargetMenuItem == .automatic)
            }
            .buttonStyle(.plain)
            .disabled(!state.hasExplicitTarget)
            .id("automatic")
            .accessibilityIdentifier("launcher-use-automatic")
            .accessibilityValue(state.hasExplicitTarget ? "" : L10n.text("launcher.target_automatic"))
            .help(L10n.text("launcher.use_automatic_help"))
            menuKeyboardHints
        }
        .font(.system(size: 12))
        .lineLimit(1)
        .padding(6)
    }

    private var menuKeyboardHints: some View {
        HStack {
            Spacer(minLength: 8)
            keyHint("↑↓", systemImage: "arrow.up.arrow.down", L10n.text("launcher.navigate"))
            keyHint("⏎", systemImage: "return", L10n.text("launcher.select"))
            keyHint("esc", systemImage: "escape", L10n.text("launcher.collapse"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func targetMenuLabel(title: String, selected: Bool, highlighted: Bool) -> some View {
        HStack(spacing: 6) {
            Text(title)
            Spacer(minLength: 8)
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accent)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(highlighted ? accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }

    private func keyHint(_ key: String, systemImage: String, _ action: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16, alignment: .center)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .accessibilityLabel(key)
            Text(action)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 拖拽把手

/// 提示条区域的拖拽把手：mouseDown 直接转交窗口拖动。
/// 编辑区保留给文本选择（NSTextView 自己消费拖拽），底部条是天然的拖动区域。
/// acceptsFirstResponder = false：拖动不会抢走编辑器焦点，也不会误触发失焦暂存。
/// 两处自动提示共用实际窗口可见判定；隐藏预建、离屏渲染和被遮挡窗口不消费机会。
struct HintPresentation: NSViewRepresentable {
    let onVisible: () -> Void

    func makeNSView(context: Context) -> VisibilityView { VisibilityView() }
    func updateNSView(_ view: VisibilityView, context: Context) {
        view.onVisible = onVisible
        view.checkPresentation()
    }

    final class VisibilityView: NSView {
        var onVisible: (() -> Void)?
        private(set) var didReport = false
        private var observers: [NSObjectProtocol] = []
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didBecomeKeyNotification, NSWindow.didResizeNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.checkPresentation() }
                })
            }
            checkPresentation()
        }

        override func layout() { super.layout(); checkPresentation() }
        override func draw(_ dirtyRect: NSRect) { checkPresentation() }

        func checkPresentation() {
            guard !didReport else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.didReport, let window = self.window,
                      window.isVisible, window.occlusionState.contains(.visible), window.alphaValue > 0,
                      !self.isHiddenOrHasHiddenAncestor, !self.visibleRect.isEmpty else { return }
                self.didReport = true
                self.onVisible?()
            }
        }

        isolated deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
}

private struct WindowDragHandle: NSViewRepresentable {
    var onClick: (() -> Void)? = nil

    func makeNSView(context: Context) -> WindowDragNSView {
        let view = WindowDragNSView()
        view.onClick = onClick
        return view
    }

    func updateNSView(_ nsView: WindowDragNSView, context: Context) {
        nsView.onClick = onClick
    }
}

private final class WindowDragNSView: NSView {
    var onClick: (() -> Void)?

    override var acceptsFirstResponder: Bool { false }

    // 失焦后第一次点击输入卡留白也要恢复编辑；拖动把手本身不占用键盘焦点。
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        onClick != nil || super.acceptsFirstMouse(for: event)
    }

    override func mouseDown(with event: NSEvent) {
        // performWindowDragWithEvent: 未导入 Swift，用经典手动拖动循环（纯公开 API）
        guard let window else { return }
        let originStart = window.frame.origin
        let mouseStart = NSEvent.mouseLocation
        let recordPanel = window as? RecordPanel
        var didDrag = false
        defer { recordPanel?.endUserDrag() }
        while true {
            guard let next = window.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp],
                until: .distantFuture,
                inMode: .default,
                dequeue: true
            ) else { break }
            if next.type == NSEvent.EventType.leftMouseUp {
                if !didDrag { onClick?() }
                break
            }
            didDrag = true
            let mouse = NSEvent.mouseLocation
            let origin = NSPoint(
                x: originStart.x + mouse.x - mouseStart.x,
                y: originStart.y + mouse.y - mouseStart.y
            )
            if let recordPanel {
                recordPanel.beginUserDrag()
                recordPanel.moveForUserDrag(to: origin)
            } else {
                window.setFrameOrigin(origin)
            }
        }
    }
}

// MARK: - NSTextView 封装

private final class EditorScrollView: NSScrollView {
    override func tile() {
        super.tile()
        (documentView as? EditorTextView)?.finishDeferredSelectionScroll()
    }
}

private struct EditorTextViewRepresentable: NSViewRepresentable {
    @Binding var text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let focusTarget: EditorFocusTarget
    let state: LauncherViewState
    let send: (LauncherEvent) -> Void
    let placeholder: String
    let automaticViewportHeightLimit: CGFloat?
    /// 文本排版高度变化上报（输入卡自动长高用；宽度变化、内容变化都会触发）。
    let onContentHeightChange: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, send: send)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = EditorScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.focusRingType = .none // 去掉聚焦时输入框四周的蓝色描边
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = EditorTextView(usingTextLayoutManager: true)
        textView.focusRingType = .none
        textView.delegate = context.coordinator
        textView.focusTarget = focusTarget
        textView.state = state
        textView.send = send
        textView.placeholder = placeholder
        textView.automaticViewportHeightLimit = automaticViewportHeightLimit
        textView.onContentHeightChange = onContentHeightChange
        let font = NSFont.systemFont(ofSize: LauncherMetrics.editorFontSize, weight: .regular)
        textView.font = font
        let paragraphStyle = NSMutableParagraphStyle()
        // 最小行高会把原生光标拉长、把字形压到行框下方；用行间距保留自然光标几何。
        let naturalLineHeight = NSLayoutManager().defaultLineHeight(for: font)
        paragraphStyle.lineSpacing = max(0, LauncherMetrics.editorLineHeight - naturalLineHeight)
        textView.defaultParagraphStyle = paragraphStyle
        textView.typingAttributes[.paragraphStyle] = paragraphStyle
        textView.textColor = EditorPalette.text
        textView.increasesContrast = colorSchemeContrast == .increased
        textView.insertionPointColor = EditorPalette.accent
        textView.reducesMotion = reduceMotion
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.allowsUndo = true
        // 全部留白由卡片承担，避免原生默认的 5pt lineFragmentPadding 再次叠加。
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        focusTarget.textView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? EditorTextView else { return }
        textView.focusTarget = focusTarget
        textView.state = state
        textView.send = send
        textView.placeholder = placeholder
        textView.automaticViewportHeightLimit = automaticViewportHeightLimit
        textView.onContentHeightChange = onContentHeightChange
        textView.reducesMotion = reduceMotion
        context.coordinator.send = send
        textView.increasesContrast = colorSchemeContrast == .increased
        textView.setPlainText(text, reason: .synchronize)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var send: (LauncherEvent) -> Void
        weak var textView: EditorTextView?

        init(text: Binding<String>, send: @escaping (LauncherEvent) -> Void) {
            _text = text
            self.send = send
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            (notification.object as? EditorTextView)?.validateTemplateSelection()
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? EditorTextView else { return }
            text = textView.string
        }

        /// 点到面板内非输入区 → 编辑器失焦 → 自动暂存草稿（§10.1）
        func textDidEndEditing(_ notification: Notification) {
            (notification.object as? EditorTextView)?.endTemplateEditing()
            send(.preserveDraft)
        }
    }
}

/// 按键语义：依当前偏好换行或提交 / Esc 取消；↑/↓ 翻阅由面板层 key monitor 统一接管。
/// IME 组词（有 marked text）期间一律放行，由输入法和系统默认行为处理。
/// placeholder 直接在 draw 里画，不经过 SwiftUI——面板侧 binding 不是
/// @Observable，SwiftUI 不会因打字触发重渲染。
final class EditorTextView: NSTextView {
    weak var focusTarget: EditorFocusTarget?
    var state: LauncherViewState!
    var send: (LauncherEvent) -> Void = { _ in }
    var placeholder = EditorView.placeholderText {
        didSet { if placeholder != oldValue { needsDisplay = true } }
    }
    /// 文本排版高度变化上报（输入卡自动长高用）。
    var onContentHeightChange: ((CGFloat) -> Void)?
    var automaticViewportHeightLimit: CGFloat? {
        didSet {
            if automaticViewportHeightLimit != oldValue, deferredSelectionScrollHeight != nil {
                reportContentHeight()
            }
        }
    }
    var reducesMotion = false {
        didSet { if reducesMotion != oldValue { updatePlaceholderVisibility() } }
    }
    var increasesContrast = false {
        didSet {
            guard increasesContrast != oldValue else { return }
            textColor = increasesContrast ? .labelColor : EditorPalette.text
            needsDisplay = true
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        textColor = increasesContrast ? .labelColor : EditorPalette.text
        insertionPointColor = increasesContrast ? .labelColor : EditorPalette.accent
        needsDisplay = true
    }

    private let placeholderStorage = NSTextContentStorage()
    private lazy var placeholderLayoutManager: NSTextLayoutManager = {
        let manager = NSTextLayoutManager()
        placeholderStorage.addTextLayoutManager(manager)
        manager.textContainer = NSTextContainer(size: .zero)
        return manager
    }()

    private var suppressesIntentReturnRepeats = false
    private var observesUndo = false
    private var lastReportedText = ""
    private var reportedComposition = false

    enum ReplacementReason {
        case synchronize
        case restoreDraft
        case newDraft
    }

    /// 程序化替换正文；组词中拒绝且不改变编辑状态。用户输入仍走原生编辑与 delegate。
    /// 新草稿身份由调用方判断：正文相同的新草稿也必须重置撤销边界。
    @discardableResult
    func setPlainText(_ text: String, reason: ReplacementReason = .synchronize) -> Bool {
        guard !hasMarkedText() else { return false }
        observeUndoChangesIfNeeded()
        let contentChanged = string != text
        if reason == .newDraft {
            breakUndoCoalescing()
            undoManager?.removeAllActions()
        }
        guard contentChanged || reason != .synchronize else { return true }
        endTemplateEditing()
        if contentChanged {
            string = text
        }
        if reason == .newDraft {
            breakUndoCoalescing()
            undoManager?.removeAllActions()
        }
        if reason != .synchronize, contentChanged || reason == .newDraft {
            setSelectedRange(NSRange(location: (string as NSString).length, length: 0))
        }
        updatePlaceholderVisibility()
        reportContentHeight()
        lastReportedText = string
        needsDisplay = true
        return true
    }

    private(set) var templateEditing: TemplateEditingSession?
    private var applyingTemplate = false
    private var movingTemplateSelection = false
    private var templateUndoSelection: (text: String, range: NSRange)?

    func endTemplateEditing() {
        guard templateEditing != nil else { return }
        templateEditing = nil
        setAccessibilityHelp(nil)
        send(.templateFillingChanged(false))
    }

    func validateTemplateSelection() {
        guard !applyingTemplate, !movingTemplateSelection, let templateEditing else { return }
        if !templateEditing.contains(selectedRange()) { endTemplateEditing() }
    }

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard super.shouldChangeText(in: affectedCharRange, replacementString: replacementString) else { return false }
        if !applyingTemplate, var session = templateEditing {
            if undoManager?.isUndoing == true || undoManager?.isRedoing == true ||
                !session.replace(affectedCharRange, withUTF16Length: (replacementString ?? "").utf16.count) {
                endTemplateEditing()
            } else { templateEditing = session }
        }
        return true
    }

    /// One native text transaction. The launcher suppresses its binding echo until this returns.
    @discardableResult
    func insertTemplate(_ expansion: TemplateExpansion) -> Bool {
        guard !hasMarkedText(), isEditable else { return false }
        observeUndoChangesIfNeeded()
        let originalText = string
        let originalSelection = selectedRange()
        let range = NSRange(location: 0, length: (string as NSString).length)
        // insertText performs shouldChangeText itself; preflighting it would register undo twice.
        endTemplateEditing()
        applyingTemplate = true
        defer { applyingTemplate = false }
        breakUndoCoalescing()
        insertText(expansion.text, replacementRange: range)
        breakUndoCoalescing()
        guard string == expansion.text else { return false }
        // AppKit restores replacement text but puts the caret at its end. Restore the
        // original selection after that native undo, within the same undo group.
        registerTemplateSelectionUndo(text: originalText, range: originalSelection)
        setSelectedRange(expansion.firstSelection)
        templateEditing = TemplateEditingSession(expansion)
        if templateEditing != nil { setAccessibilityHelp(L10n.text("templates.filling_help")) }
        send(.templateFillingChanged(templateEditing != nil))
        updatePlaceholderVisibility()
        reportContentHeight()
        lastReportedText = string
        return true
    }

    /// Append the capture as one native undoable edit, before the panel is shown.
    @discardableResult
    func insertCapturedQuotation(_ quotation: String) -> Bool {
        guard !hasMarkedText(), isEditable, !quotation.isEmpty else { return false }
        observeUndoChangesIfNeeded()
        let original = string, selection = selectedRange()
        let separator = original.isEmpty || original.hasSuffix("\n\n") ? "" : (original.hasSuffix("\n") ? "\n" : "\n\n")
        let insertion = separator + quotation
        endTemplateEditing()
        breakUndoCoalescing()
        insertText(insertion, replacementRange: NSRange(location: (original as NSString).length, length: 0))
        breakUndoCoalescing()
        guard string == original + insertion else { return false }
        registerTemplateSelectionUndo(text: original, range: selection)
        return true
    }

    private func registerTemplateSelectionUndo(text: String, range: NSRange) {
        undoManager?.registerUndo(withTarget: self) { editor in
            editor.templateUndoSelection = (text, range)
            // Redo restores only the text; retain the selection restoration for a later Undo.
            editor.undoManager?.registerUndo(withTarget: editor) { editor in
                editor.registerTemplateSelectionUndo(text: text, range: range)
            }
        }
    }

    private func navigateTemplate(forward: Bool) {
        guard var session = templateEditing else { return }
        let destination = session.move(forward: forward)
        templateEditing = session
        movingTemplateSelection = true
        let text = string as NSString
        let location = min(destination.selection.location, text.length)
        let safe: NSRange
        if destination.selection.length > 0, NSMaxRange(destination.selection) <= text.length {
            safe = text.rangeOfComposedCharacterSequences(for: destination.selection)
        } else if location < text.length {
            safe = NSRange(location: text.rangeOfComposedCharacterSequence(at: location).location, length: 0)
        } else { safe = NSRange(location: location, length: 0) }
        setSelectedRange(safe)
        scrollRangeToVisible(safe)
        movingTemplateSelection = false
        if destination.finished { endTemplateEditing() }
    }

    /// 粘贴与拖放只接收文字。富文本降级为字符，附件占位符被移除；图片和文件不写入正文。
    @discardableResult
    func insertPlainText(from pasteboard: NSPasteboard) -> Bool {
        guard !hasMarkedText(), pasteboard.types?.contains(.fileURL) != true,
              let text = plainText(from: pasteboard), !text.isEmpty else { return false }
        breakUndoCoalescing()
        insertText(text, replacementRange: selectedRange())
        breakUndoCoalescing()
        return true
    }

    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        [.string, .rtfd, .rtf, .html]
    }

    override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        [.string, .rtfd, .rtf, .html]
    }

    override func readSelection(from pasteboard: NSPasteboard) -> Bool {
        insertPlainText(from: pasteboard)
    }

    override func readSelection(from pasteboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        insertPlainText(from: pasteboard)
    }

    private func plainText(from pasteboard: NSPasteboard) -> String? {
        if let text = pasteboard.string(forType: .string) { return text }
        let attributed: NSAttributedString?
        if let data = pasteboard.data(forType: .rtfd) {
            attributed = NSAttributedString(rtfd: data, documentAttributes: nil)
        } else if let data = pasteboard.data(forType: .rtf) {
            attributed = NSAttributedString(rtf: data, documentAttributes: nil)
        } else if let data = pasteboard.data(forType: .html) {
            attributed = NSAttributedString(html: data, documentAttributes: nil)
        } else {
            attributed = nil
        }
        return attributed?.string.replacingOccurrences(of: "\u{FFFC}", with: "")
    }

    private var contentHeightReportScheduled = false
    private var deferredSelectionScrollHeight: CGFloat?

    override func scrollToVisible(_ rect: NSRect) -> Bool {
        if let limit = automaticViewportHeightLimit, let scrollView = enclosingScrollView,
           scrollView.contentSize.height + 0.5 < limit,
           frame.height > scrollView.contentSize.height + 0.5,
           rect.maxY > visibleRect.maxY {
            // Native editing reveals the caret before SwiftUI grows the viewport.
            // Wait for that growth instead of scrolling up and immediately back down.
            deferredSelectionScrollHeight = .greatestFiniteMagnitude
            reportContentHeight()
            return true
        }
        return super.scrollToVisible(rect)
    }

    fileprivate func finishDeferredSelectionScroll() {
        guard let height = deferredSelectionScrollHeight, let scrollView = enclosingScrollView,
              scrollView.contentSize.height + 0.5 >= height else { return }
        deferredSelectionScrollHeight = nil
        scrollRangeToVisible(selectedRange())
    }

    /// Coalesce text and viewport changes after AppKit finishes the editing transaction.
    func reportContentHeight() {
        guard !contentHeightReportScheduled else { return }
        contentHeightReportScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.contentHeightReportScheduled = false
            self.publishContentHeight()
        }
    }

    private func publishContentHeight() {
        let timing = InputPerformance.begin()
        defer { InputPerformance.end("height", timing) }
        guard let onContentHeightChange, let textLayoutManager else { return }
        var height: CGFloat = 0
        var lastTextLine: (fragment: NSTextLayoutFragment, line: NSTextLineFragment)?
        // usageBoundsForTextContainer can retain a deleted trailing paragraph's height.
        // Measure the current fragments, including the extra insertion line, instead.
        textLayoutManager.enumerateTextLayoutFragments(
            from: textLayoutManager.documentRange.location,
            options: [.ensuresLayout, .ensuresExtraLineFragment]
        ) { fragment in
            height = max(height, fragment.layoutFragmentFrame.maxY)
            if let line = fragment.textLineFragments.last(where: { $0.characterRange.length > 0 }) {
                lastTextLine = (fragment, line)
            }
            return true
        }
        // Preserve ink extending below the final text line, including tall fallback glyphs.
        if let (fragment, line) = lastTextLine {
            let content = line.attributedString.attributedSubstring(from: line.characterRange)
            let ink = CTLineGetImageBounds(CTLineCreateWithAttributedString(content), nil)
            if !ink.isNull, !ink.isInfinite {
                let baseline = fragment.layoutFragmentFrame.minY + line.typographicBounds.minY + line.glyphOrigin.y
                height = max(height, baseline - ink.minY)
            }
        }
        height = ceil(height)
        // The scrollable document must follow both increases and decreases in content.
        let documentHeight = max(height, enclosingScrollView?.contentSize.height ?? 0)
        if abs(frame.height - documentHeight) > 0.5 {
            super.setFrameSize(NSSize(width: frame.width, height: documentHeight))
        }
        if deferredSelectionScrollHeight != nil {
            deferredSelectionScrollHeight = automaticViewportHeightLimit.map { min(height, $0) } ?? 0
        }
        onContentHeightChange(height)
        finishDeferredSelectionScroll()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        reportContentHeight()
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        super.insertText(insertString, replacementRange: replacementRange)
        updatePlaceholderVisibility()
        reportComposition(hasMarkedText())
    }

    override func unmarkText() {
        super.unmarkText()
        updatePlaceholderVisibility()
        reportComposition(hasMarkedText())
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        reportComposition(true)
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        updatePlaceholderVisibility()
        reportComposition(hasMarkedText())
    }

    private func reportComposition(_ composing: Bool) {
        guard composing != reportedComposition else { return }
        reportedComposition = composing
        send(.compositionChanged(composing))
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !hasMarkedText(), placeholderAlpha > 0.01,
              let context = NSGraphicsContext.current?.cgContext else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        context.setAlpha(placeholderAlpha)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.preferredFont(forTextStyle: .body),
            .foregroundColor: increasesContrast ? NSColor.secondaryLabelColor : EditorPalette.secondary,
            .paragraphStyle: defaultParagraphStyle ?? NSParagraphStyle.default,
        ]
        // 和正文一样通过 TextKit 2 排版，不用绘制偏移补偿基线。
        let layout = placeholderLayoutManager
        layout.textContainer?.size = NSSize(width: textContainer?.size.width ?? bounds.width,
                                            height: .greatestFiniteMagnitude)
        layout.textContainer?.lineFragmentPadding = textContainer?.lineFragmentPadding ?? 0
        placeholderStorage.textStorage?.setAttributedString(NSAttributedString(string: placeholder, attributes: attributes))
        layout.enumerateTextLayoutFragments(from: layout.documentRange.location, options: [.ensuresLayout]) { fragment in
            fragment.draw(at: NSPoint(x: self.textContainerOrigin.x + fragment.layoutFragmentFrame.minX,
                                      y: self.textContainerOrigin.y + fragment.layoutFragmentFrame.minY), in: context)
            return true
        }
    }

    // MARK: - Placeholder 淡入淡出

    private var placeholderAlpha: CGFloat = 1
    private var placeholderTarget: CGFloat = 1
    private var placeholderTimer: Timer?

    /// 有正文或组词时立即让位；仅删空时淡入，旧计时器不能重画 placeholder。
    private func updatePlaceholderVisibility() {
        let target: CGFloat = (string.isEmpty && !hasMarkedText()) ? 1 : 0
        if target == 0 || reducesMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            placeholderTimer?.invalidate()
            placeholderTimer = nil
            placeholderTarget = target
            placeholderAlpha = target
            needsDisplay = true
            return
        }
        guard target != placeholderTarget else { return }
        placeholderTarget = target
        placeholderTimer?.invalidate()
        let from = placeholderAlpha
        let start = CFAbsoluteTimeGetCurrent()
        let duration: CFAbsoluteTime = 0.15
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            let timerID = ObjectIdentifier(timer)
            MainActor.assumeIsolated {
                guard let self, self.placeholderTimer.map(ObjectIdentifier.init) == timerID,
                      self.string.isEmpty, !self.hasMarkedText() else { return }
                let p = CGFloat(min((CFAbsoluteTimeGetCurrent() - start) / duration, 1))
                self.placeholderAlpha = from + (target - from) * p
                self.needsDisplay = true
                if p >= 1 {
                    self.placeholderTimer?.invalidate()
                    self.placeholderTimer = nil
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        placeholderTimer = timer
    }

    override func didChangeText() {
        let timing = InputPerformance.begin()
        defer { InputPerformance.end("edit", timing) }
        super.didChangeText()
        observeUndoChangesIfNeeded()
        lastReportedText = string
        updatePlaceholderVisibility()
        reportContentHeight()
    }

    private func observeUndoChangesIfNeeded() {
        guard !observesUndo else { return }
        observesUndo = true
        lastReportedText = string
        for name in [Notification.Name.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange] {
            NotificationCenter.default.addObserver(self, selector: #selector(undoFinished), name: name, object: nil)
        }
    }

    @objc private func undoFinished(_ notification: Notification) {
        guard notification.object as? UndoManager === undoManager else { return }
        endTemplateEditing()
        if string != lastReportedText { didChangeText() }
        if let selection = templateUndoSelection, string == selection.text,
           NSMaxRange(selection.range) <= (string as NSString).length {
            setSelectedRange(selection.range)
        }
        templateUndoSelection = nil
    }

    isolated deinit {
        placeholderTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    override func keyDown(with event: NSEvent) {
        // 非激活面板下 app 不激活，主菜单 key equivalent 路由（Cmd+C/V/X/A/Z）不可用：
        // 菜单匹配失败后事件穿透到 keyDown，若不接手则整组编辑快捷键全断。
        // 这里手动派发到对应动作。
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods.contains(.command), !hasMarkedText() {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "v":
                paste(self)
                return
            case "c":
                copy(self)
                return
            case "x":
                cut(self)
                return
            case "a":
                selectAll(nil)
                return
            case "z":
                endTemplateEditing()
                if mods.contains(.shift) { undoManager?.redo() } else { undoManager?.undo() }
                return
            default:
                break
            }
        }
        guard !hasMarkedText() else {
            super.keyDown(with: event)
            return
        }

        // Review is read-only: Esc closes and Tab reaches the footer controls.
        // so the hidden editor doesn't mutate under the overlay.
        if state.showsReview {
            if event.keyCode == 0x35, !event.isARepeat { send(.closeReview) }
            else if event.keyCode == 0x30, !event.isARepeat,
                    mods.intersection([.command, .control, .option]).isEmpty {
                if mods.contains(.shift) { _ = focusTarget?.focusReview(last: true) }
                else { focusTarget?.focusModeControl() }
            }
            return
        }

        if templateEditing != nil {
            if event.keyCode == 0x30, mods.intersection([.command, .control, .option]).isEmpty {
                if !event.isARepeat { navigateTemplate(forward: !mods.contains(.shift)) }
                return
            }
            if event.keyCode == 0x35 { endTemplateEditing(); return }
        }

        let isReturn = event.keyCode == 0x24 || event.keyCode == 0x4C // 回车 / 小键盘回车
        let returnModifiers = mods.intersection([.command, .control, .option, .shift])
        if event.keyCode == 0x30, returnModifiers == .shift, !state.isTemplateMenuVisible {
            if !event.isARepeat, focusTarget?.focusThinkingPrompt() != true,
               focusTarget?.focusReview(last: true) != true, focusTarget?.focusRecentDocument(last: true) != true {
                focusTarget?.focusModeControl()
            }
            return
        }
        if state.mode == .sticky {
            if isReturn {
                if returnModifiers.isEmpty || returnModifiers == .shift { insertNewline(nil) }
                return
            }
            if event.keyCode == 0x35 {
                if !event.isARepeat { send(.cancel) }
                return
            }
            super.keyDown(with: event)
            return
        }
        if isReturn, event.isARepeat, suppressesIntentReturnRepeats { return }
        if !event.isARepeat { suppressesIntentReturnRepeats = false }
        // @ completion consumes confirmation before the normal execution path, including Cmd+Enter.
        if let focusTarget, state.isTemplateMenuVisible {
            if event.keyCode == 0x35 {
                send(.dismissTemplateMenu)
                return
            }
            if returnModifiers.isEmpty, event.keyCode == 0x7E || event.keyCode == 0x7D {
                if !event.isARepeat { focusTarget.moveTemplateFocus(forward: event.keyCode == 0x7D, state: state) }
                return
            }
            if event.keyCode == 0x30, returnModifiers.isEmpty || returnModifiers == .shift {
                focusTarget.moveTemplateFocus(forward: returnModifiers.isEmpty, state: state)
                return
            }
            if isReturn {
                if returnModifiers == .shift {
                    insertNewline(nil)
                } else if returnModifiers.isEmpty || returnModifiers == .command {
                    suppressesIntentReturnRepeats = true
                    if !event.isARepeat { focusTarget.selectHighlightedTemplate(state: state, send: send) }
                }
                return
            }
        }
        if isReturn, returnModifiers == .command, focusTarget != nil,
           state.isIntentRecognitionEnabled,
           !state.isIntentCandidateMenuVisible,
           !state.isReadingGettingStarted {
            if !event.isARepeat { send(.confirm(.commandEnter)) }
            return // Never submit a record or queue a future action while recognition is pending.
        }
        // 菜单里的导航不修改路由；只有 Enter 才选定目标或恢复自动。
        if let focusTarget, state.isIntentCandidateMenuVisible {
            if event.keyCode == 0x35 { // Esc 先收选择器
                send(.candidateMenuChanged(false))
                return
            }
            if returnModifiers.isEmpty, event.keyCode == 0x7E || event.keyCode == 0x7D {
                if !event.isARepeat { focusTarget.moveTargetMenuFocus(forward: event.keyCode == 0x7D, state: state) }
                return
            }
            if event.keyCode == 0x30, returnModifiers.isEmpty || returnModifiers == .shift {
                focusTarget.moveTargetMenuFocus(forward: returnModifiers.isEmpty, state: state)
                return
            }
            if isReturn {
                suppressesIntentReturnRepeats = true
                if !event.isARepeat { focusTarget.selectHighlightedTarget(state: state, send: send) }
                return
            }
        }
        if state.clipboardHistory != nil, returnModifiers.isEmpty,
           event.keyCode == 0x7E || event.keyCode == 0x7D {
            send(.clipboardMove(forward: event.keyCode == 0x7D))
            return
        }
        // Tab 把真实键盘焦点移到目标胶囊；关闭菜单后回到原编辑选区。
        if let focusTarget, state.canChooseTarget,
           !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, event.keyCode == 0x30,
           returnModifiers.isEmpty || returnModifiers == .shift {
            if !event.isARepeat { focusTarget.targetSelectorFocusRequest += 1 }
            return
        }
        // ⌥↑/⌥↓：在 Notes 与 Codex 之间切换（仅当有多个目标可切换时拦截）。
        if focusTarget != nil, state.intentCanCycle,
           state.isIntentRecognitionEnabled,
           !state.isReadingGettingStarted,
           returnModifiers == .option, event.keyCode == 0x7E || event.keyCode == 0x7D {
            if !event.isARepeat { send(.cycleTarget(forward: event.keyCode == 0x7D)) } // 0x7D=下=forward
            return
        }
        if isReturn, returnModifiers.isEmpty || returnModifiers == .shift {
            if returnModifiers == .shift {
                insertNewline(nil) // 原生编辑：替换选区并支持撤销
                return
            }
            // ⏎ 永远执行当前目标，不区分识别是否已落地。
            if focusTarget != nil, state.isIntentRecognitionEnabled {
                suppressesIntentReturnRepeats = true
                if !event.isARepeat { send(.confirm(.enter)) }
                return
            }
        }
        if event.keyCode == 0x35 { // Esc
            guard !event.isARepeat else { return }
            send(.cancel)
            return
        }
        super.keyDown(with: event)
    }
}
