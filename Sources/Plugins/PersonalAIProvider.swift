import Foundation

/// Setup shortcuts, inferred from the saved destination without changing its schema.
enum PersonalAIProvider: CaseIterable {
    case deepSeek, kimi, openAI, claude, custom

    var title: String {
        switch self {
        case .deepSeek: "DeepSeek"
        case .kimi: "Kimi"
        case .openAI: "OpenAI"
        case .claude: "Claude"
        case .custom: L10n.text("settings.ai.personal.custom")
        }
    }

    var service: PersonalModelConfiguration.Service {
        self == .claude ? .claude : .openAICompatible
    }

    var baseURL: String {
        switch self {
        case .deepSeek: "https://api.deepseek.com"
        case .kimi: "https://api.moonshot.cn/v1"
        case .openAI: "https://api.openai.com/v1"
        case .claude: "https://api.anthropic.com/v1"
        case .custom: ""
        }
    }

    var keyURL: URL? {
        let address: String
        switch self {
        case .deepSeek: address = "https://platform.deepseek.com/api_keys"
        case .kimi: address = "https://platform.kimi.com/console/api-keys"
        case .openAI: address = "https://platform.openai.com/api-keys"
        case .claude: address = "https://platform.claude.com/settings/keys"
        case .custom: return nil
        }
        return URL(string: address)
    }

    static func matching(_ configuration: PersonalModelConfiguration) -> Self {
        guard let value = try? configuration.normalizedDestination() else { return .custom }
        return allCases.first {
            $0 != .custom && value.service == $0.service &&
            (value.baseURL == $0.baseURL || ($0 == .deepSeek && value.baseURL == $0.baseURL + "/v1"))
        } ?? .custom
    }
}
