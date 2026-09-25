import Foundation
import Observation

/// 悬浮层里的一个候选路由目标（Jev 建议或其余可用目标）。
struct IntentCandidate: Equatable, Identifiable {
    let id: String
    let title: String
    let isSelected: Bool
}

/// 会话提供给界面的只读状态；所有变化由 `LauncherSession.send(_:)` 驱动。
@MainActor @Observable
final class LauncherViewState {
    var draftContent = ""
    var hasPreparedDraft = false
    var hasUnsavedChanges = false
    var hasFailedSubmission = false
    var message: String?
    var isReadingGettingStarted = false
    var isComposingText = false
    var intentTitle: String?
    /// 当前会话是否有可手动选择的目标（不依赖 Jev 是否给出建议）。
    var intentCanCycle = false
    /// 用户是否已明确指定目标，即使指定目标恰好等于建议也为 true。
    var intentDeviated = false
    var intentStatus: String?
    var intentIssue: String?
    /// 悬浮层候选目标列表（含当前选中项，非选中项显形可点）。
    var intentCandidates: [IntentCandidate] = []
    /// 动作行显示的可执行动作标题；与按 Enter 实际执行的动作共用同一解析结果。
    var displayedActionTitle: String?
    var isIntentCandidateMenuVisible = false
    var isIntentRecognitionEnabled = false
    var isOpeningApplication = false
    var lastEventSucceeded = true
}
