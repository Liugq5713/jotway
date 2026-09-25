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
}

/// action 执行前即可确定的窗口策略。
enum PresentationPolicy: Sendable, Equatable {
    case returnToPreviousApplication
    case keepDestinationFrontmost
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
    let presentationPolicy: PresentationPolicy

    init(id: String, title: String, settingsName: String, summary: String,
         titleKey: String? = nil, settingsNameKey: String? = nil, summaryKey: String? = nil,
         systemImageName: String, tint: ActionTint, settingsGroup: ActionSettingsGroup,
         enablementPolicy: ActionEnablementPolicy, fallbackPriority: Int?,
         intentHints: IntentHints, presentationPolicy: PresentationPolicy) {
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
        self.presentationPolicy = presentationPolicy
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
}

struct PreparedAction: Sendable {
    let actionID: String
    let inputIdentity: ActionInput.Identity
    let execute: @MainActor @Sendable () async throws -> ActionOutcome
}

/// 执行结果，结构化返回，由输入层决定如何反馈。
struct ActionOutcome: Sendable {
    /// 面板反馈文案，例如「已存入备忘录」。
    var message: String?
    var messageKey: String?
    var messageArguments: [String]

    init(message: String? = nil, messageKey: String? = nil, messageArguments: [String] = []) {
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

/// 喂给意图识别的判别线索。不是关键词列表，而是消歧文案（识别准确率取决于它）。
struct IntentHints: Sendable, Equatable {
    /// 本地关键词 / 前缀匹配规则（逃生舱）：jev 描述难写时可退化成本地匹配，不依赖模型。
    var localKeywords: [String] = []
    /// Jev 固定语义的可选绑定；普通 action 默认不进入模型协议。
    var modelBinding: ModelBinding = .none

    enum ModelBinding: Sendable, Equatable {
        case none
        case capture(criteria: String)
        case webSearch
    }
}
