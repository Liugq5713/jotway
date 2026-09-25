import Foundation

/// Action 与宿主之间的脱敏错误边界。只有这里的 message 可以直接展示给用户。
struct ActionFailure: Error, LocalizedError, RuntimeLogError, Sendable {
    private let literalMessage: String?
    private let messageKey: String?
    private let messageArguments: [String]
    let code: RuntimeLog.Code
    let osStatus: Int?

    init(_ message: String, code: RuntimeLog.Code = .unknown, osStatus: Int? = nil) {
        literalMessage = message
        messageKey = nil
        messageArguments = []
        self.code = code
        self.osStatus = osStatus
    }

    init(localized key: String, arguments: [String] = [],
         code: RuntimeLog.Code = .unknown, osStatus: Int? = nil) {
        literalMessage = nil
        messageKey = key
        messageArguments = arguments
        self.code = code
        self.osStatus = osStatus
    }

    var message: String {
        if let messageKey {
            return AppLocalization.shared.string(messageKey, arguments: messageArguments.map { $0 as CVarArg })
        }
        return literalMessage ?? L10n.text("error.generic")
    }

    var errorDescription: String? { message }
    var runtimeLogCode: RuntimeLog.Code { code }

    static func presentation(for error: Error) -> ActionFailure {
        if let failure = error as? ActionFailure { return failure }
        if error is CancellationError { return ActionFailure(localized: "error.cancelled", code: .cancelled) }
        return ActionFailure(localized: "error.generic", code: RuntimeLog.code(error))
    }
}

/// 兼容仍使用发送错误工厂的实现；返回统一安全错误，不暴露外部 SDK 文案。
func sendFailure(_ message: String) -> ActionFailure {
    ActionFailure(message)
}
