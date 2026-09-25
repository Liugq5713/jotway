import Foundation

/// English is the only shipped UI language. Semantic keys and a standard SwiftPM resource bundle
/// keep the boundary ready for a future additional localization without coupling business state to copy.
final class AppLocalization: Sendable {
    static let shared = AppLocalization()
    private init() {}

    private static let resourceBundle: Bundle = {
        // 原生应用从 Contents/Resources 读取；SwiftPM 开发与测试使用生成的资源入口。
        let packagedBundle = Bundle.main.url(forResource: "Jotway_Jotway", withExtension: "bundle")
            .flatMap { Bundle(url: $0) }
        return packagedBundle ?? .module
    }()

    func string(_ key: String, arguments: [CVarArg] = []) -> String {
        let format = localizedFormat(key) ?? key
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: Locale(identifier: "en"), arguments: arguments)
    }

    private func localizedFormat(_ key: String) -> String? {
        guard let path = Self.resourceBundle.path(forResource: "en", ofType: "lproj"),
              let bundle = Bundle(path: path) else { return nil }
        let missing = "__JOTWAY_MISSING_\(key)__"
        let value = bundle.localizedString(forKey: key, value: missing, table: nil)
        return value == missing ? nil : value
    }
}

enum L10n {
    static func text(_ key: String, _ arguments: CVarArg...) -> String {
        AppLocalization.shared.string(key, arguments: arguments)
    }
}
