import Foundation
import Observation

enum LauncherMode {
    case quickInput
    case sticky
}

/// 悬浮层里的一个候选路由目标（本地应用建议或其余可用目标）。
struct IntentCandidate: Equatable, Identifiable {
    let id: String
    let title: String
    let isSelected: Bool
}

/// 会话提供给界面的只读状态；所有变化由 `LauncherSession.send(_:)` 驱动。
@MainActor @Observable
final class LauncherViewState {
    var thinkingPrompt: DraftThinkingPromptSession?
    var mode: LauncherMode = .quickInput
    /// Invalidates geometry and presentation callbacks across mode changes.
    var modeGeneration = UUID()
    var isAcceptingSubmission = false
    var modeSwitchBlockReason: String? {
        if isComposingText { return L10n.text("launcher.mode.blocked.composition") }
        if isReadingGettingStarted { return L10n.text("launcher.mode.blocked.onboarding") }
        if isConfiguringAction { return L10n.text("launcher.mode.blocked.setup") }
        if isAcceptingSubmission || isOpeningApplication { return L10n.text("launcher.mode.blocked.submission") }
        return nil
    }
    var draftContent = ""
    var hasPreparedDraft = false
    var hasUnsavedChanges = false
    var hasFailedSubmission = false
    var message: String?
    var isReadingGettingStarted = false
    var isComposingText = false
    var intentTitle: String?
    /// 选择入口与目标循环分开：只有一个目标也能打开选择菜单。
    var canChooseTarget = false
    var hasExplicitTarget = false
    var isFillingTemplate = false
    var clipboardHistory: ClipboardHistory?
    var showsCodexRecentTasks = false
    /// Periodic review surface opened explicitly from the capture panel.
    var showsReview = false
    var reviewPeriod: NotesReviewPeriod = .weekly
    var reviewSummary: NotesReviewSummary?
    var reviewPreview: NotesReviewSummary?
    var reviewRequestMetadata: NotesReviewMetadata?
    var isLoadingReview = false
    var reviewFailed = false
    var reviewCoverageIncomplete = false
    var reviewUnavailableReason: String?
    var recentDocuments: [RecentSavedDocument] = []
    var canShowRecentDocuments = false
    var selectedRecentDocumentID: String?
    var recentDocumentText: String?
    var recentDocumentError: String?
    var isLoadingRecentDocument = false
    var selectedRecentDocument: RecentSavedDocument? {
        recentDocuments.first { $0.id == selectedRecentDocumentID }
    }
    var recentDocumentPosition: Int? {
        recentDocuments.firstIndex { $0.id == selectedRecentDocumentID }
    }
    var canShowNewerRecentDocument: Bool { recentDocumentPosition.map { $0 > 0 } ?? false }
    var canShowOlderRecentDocument: Bool {
        recentDocumentPosition.map { $0 + 1 < recentDocuments.count } ?? false
    }
    var templateCandidates: [InputTemplate] = []
    var isTemplateMenuVisible: Bool { !templateCandidates.isEmpty }
    /// 当前是否能接收确认；具体可用性和准备身份仍由会话校验。
    var canConfirm = false
    /// 是否存在与当前目标不同的候选，供 Option 上下键循环。
    var intentCanCycle = false
    /// 用户是否已明确指定目标，即使指定目标恰好等于建议也为 true。
    var intentDeviated = false
    var intentStatus: String?
    var intentIssue: String?
    /// 悬浮层候选目标列表（含当前选中项，非选中项显形可点）。
    var intentCandidates: [IntentCandidate] = []
    /// 动作行显示的执行或配置标题；与按 Enter 的行为共用同一解析结果。
    var displayedActionTitle: String?
    var displayedActionIcon: String?
    var panelSessionID = UUID()
    var preparationFailure: String?
    var isPreparingAction = false
    var isIntentCandidateMenuVisible = false
    var isIntentRecognitionEnabled = false
    var isOpeningApplication = false
    var isConfiguringAction = false
    var lastEventSucceeded = true
}
