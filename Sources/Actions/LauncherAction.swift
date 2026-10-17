import Foundation

/// 启动器能力层的支点（见 launcher-refactor.md §2A.2）。
///
/// 一个 action 把自己全部的东西挂在自己身上——识别线索、配置项、可用性、执行——
/// 不散落在路由 / 引擎 / 输入 / 设置四处。这是「独立」的结构保证：
/// 加一个 action = 新建一个文件 + 注册一行。
protocol LauncherAction: Sendable {
    /// action 对外唯一的静态描述；UI、配置和路由不再按具体 id 推断元数据。
    var descriptor: ActionDescriptor { get }
    /// 一次性完成加工与执行闭包冻结；预览和 Enter 复用同一个 PreparedAction。
    func prepare(_ input: ActionInput) async throws -> PreparedAction
    func preparation(for input: ActionInput) throws -> ActionPlan
}

extension LauncherAction {
    func preparation(for input: ActionInput) throws -> ActionPlan {
        let planID = UUID()
        return ActionPlan(id: planID, actionID: descriptor.id, inputIdentity: input.identity) {
            let value = try await prepare(input)
            return PreparedAction(actionID: value.actionID, inputIdentity: value.inputIdentity,
                                  planID: planID, execute: value.execute)
        }
    }

    func prepare(_ input: ActionInput) async throws -> PreparedAction {
        try await preparation(for: input).build()
    }
}

struct ActionPlan: Sendable {
    var id = UUID()
    let actionID: String
    let inputIdentity: ActionInput.Identity
    let build: @Sendable () async throws -> PreparedAction
}

/// action 执行前即可确定的窗口策略。
enum PresentationPolicy: Sendable, Equatable {
    case returnToPreviousApplication
    case keepDestinationFrontmost
    case keepPanelOpen
}

enum ActionPreparationTiming: Sendable, Equatable {
    case beforeConfirmation
    /// Background work after the draft is accepted and the panel is hidden.
    case afterConfirmation
    /// Confirm first, then prepare while the editable draft and target still own the request.
    case beforeSubmission
}

struct ActionDescriptor: Sendable, Equatable {
    let id: String
    let title: String
    let settingsName: String
    let summary: String
    let titleKey: String?
    let settingsNameKey: String?
    let summaryKey: String?
    let systemImageName: String
    let tint: ActionTint
    let settingsGroup: ActionSettingsGroup
    let enablementPolicy: ActionEnablementPolicy
    let fallbackPriority: Int?
    let intentHints: IntentHints
    let requiresExplicitSelection: Bool
    let presentationPolicy: PresentationPolicy
    /// Original-preserving actions consume `ActionInput.originalText` instead of its trimmed body.
    let preservesOriginalText: Bool
    let preparationTiming: ActionPreparationTiming
    /// Destination to activate when the user clicks a completion notice.
    let applicationBundleIdentifier: String?

    init(id: String, title: String, settingsName: String, summary: String,
         titleKey: String? = nil, settingsNameKey: String? = nil, summaryKey: String? = nil,
         systemImageName: String, tint: ActionTint, settingsGroup: ActionSettingsGroup,
         enablementPolicy: ActionEnablementPolicy, fallbackPriority: Int?,
         intentHints: IntentHints, presentationPolicy: PresentationPolicy,
         requiresExplicitSelection: Bool = false,
         preservesOriginalText: Bool = false,
         preparationTiming: ActionPreparationTiming = .beforeConfirmation,
         applicationBundleIdentifier: String? = nil) {
        self.id = id
        self.title = title
        self.settingsName = settingsName
        self.summary = summary
        self.titleKey = titleKey
        self.settingsNameKey = settingsNameKey
        self.summaryKey = summaryKey
        self.systemImageName = systemImageName
        self.tint = tint
        self.settingsGroup = settingsGroup
        self.enablementPolicy = enablementPolicy
        self.fallbackPriority = fallbackPriority
        self.intentHints = intentHints
        self.requiresExplicitSelection = requiresExplicitSelection
        self.presentationPolicy = presentationPolicy
        self.preservesOriginalText = preservesOriginalText
        self.preparationTiming = preparationTiming
        self.applicationBundleIdentifier = applicationBundleIdentifier
    }

    var localizedTitle: String { titleKey.map { L10n.text($0) } ?? title }
    var localizedSettingsName: String { settingsNameKey.map { L10n.text($0) } ?? settingsName }
    var localizedSummary: String { summaryKey.map { L10n.text($0) } ?? summary }

    var canBeDefault: Bool { fallbackPriority != nil }
}

enum ActionTint: String, Sendable, Equatable {
    case orange, teal, red, green, blue
}

struct ActionSettingsGroup: Sendable, Equatable, Hashable {
    let id: String
    let title: String
    let order: Int
    let titleKey: String?

    init(id: String, title: String, order: Int, titleKey: String? = nil) {
        self.id = id
        self.title = title
        self.order = order
        self.titleKey = titleKey
    }

    var localizedTitle: String { titleKey.map { L10n.text($0) } ?? title }
}

enum ActionEnablementPolicy: Sendable, Equatable {
    case alwaysEnabled
    case userToggle(defaultEnabled: Bool)
}

struct ActionInput: Sendable {
    struct Identity: Hashable, Sendable {
        let draftID: UUID
        let revision: Int
    }

    let identity: Identity
    let text: String
    /// Exact frozen editor content. Existing actions retain the trimmed `text` contract.
    let originalText: String

    init(identity: Identity, text: String, originalText: String? = nil) {
        self.identity = identity
        self.text = text
        self.originalText = originalText ?? text
    }
}

struct PreparedAction: Sendable {
    let actionID: String
    let inputIdentity: ActionInput.Identity
    let planID: UUID?
    let execute: @MainActor @Sendable () async throws -> ActionOutcome

    init(actionID: String, inputIdentity: ActionInput.Identity, planID: UUID? = nil,
         execute: @escaping @MainActor @Sendable () async throws -> ActionOutcome) {
        self.actionID = actionID
        self.inputIdentity = inputIdentity
        self.planID = planID
        self.execute = execute
    }
}

enum ActionCompletionDestination: Sendable {
    case application(bundleIdentifier: String)
    case url(URL, fallback: URL)
}

/// 执行结果，结构化返回，由输入层决定如何反馈。
struct ActionOutcome: Sendable {
    /// 目标系统实际确认的效果；未提供凭据的扩展 action 保持 unknown。
    let effect: OperationExecutionOutcome
    /// Opt in to immediate, non-activating feedback after the confirmed result.
    let showsCompletionNotice: Bool
    /// A task-specific destination overrides opening the action's application.
    let completionDestination: ActionCompletionDestination?
    /// The opaque ID of a confirmed Notes save, for reopening that document.
    let savedNoteID: String?
    /// 面板反馈文案，例如「已存入备忘录」。
    var message: String?
    var messageKey: String?
    var messageArguments: [String]

    init(message: String? = nil, messageKey: String? = nil, messageArguments: [String] = [],
         effect: OperationExecutionOutcome = .unknown, showsCompletionNotice: Bool = false,
         completionDestination: ActionCompletionDestination? = nil, savedNoteID: String? = nil) {
        self.effect = effect
        self.showsCompletionNotice = showsCompletionNotice
        self.completionDestination = completionDestination
        self.savedNoteID = savedNoteID
        self.message = message
        self.messageKey = messageKey
        self.messageArguments = messageArguments
    }

    var localizedMessage: String? {
        if let messageKey {
            return AppLocalization.shared.string(messageKey, arguments: messageArguments.map { $0 as CVarArg })
        }
        return message
    }
}

/// Explicit local routing keywords; no model classification is performed.
struct IntentHints: Sendable, Equatable {
    var localKeywords: [String] = []
}
