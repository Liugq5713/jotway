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
    /// 选择入口与目标循环分开：只有一个目标也能打开选择菜单。
    var canChooseTarget = false
    var hasExplicitTarget = false
    /// 当前是否能接收确认；具体可用性和时间计划仍由会话校验。
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
    /// Space only: never retains a plan, its text, or its presentation receipt.
    var reservesPlanResultSpace = false
    var planSummary: ActionPlanSummary?
    var planContext: ScheduleContext?
    var currentPlanID: UUID?
    var panelSessionID = UUID()
    var presentedPlanID: UUID?
    var timeIssue: TimeInputIssue?
    var preparationFailure: String?
    var isPreparingAction = false
    var isCheckingActionPlan = false
    var isIntentCandidateMenuVisible = false
    var isIntentRecognitionEnabled = false
    var isOpeningApplication = false
    var isConfiguringAction = false
    var lastEventSucceeded = true
}
