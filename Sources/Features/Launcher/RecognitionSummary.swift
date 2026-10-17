import Foundation

/// Recognition metadata is independent of any persistence or confirmation model.
struct RecognitionSummary: Codable, Equatable, Sendable {
    let source: RecognitionSource
    let requestID: UUID?
    let ruleVersion: String?
    let actualModel: String?
    var applicationMatch: RecognitionApplicationMatch? = nil
}

enum RecognitionSource: String, Codable, Sendable { case model, localAppName = "local_app_name" }
enum RecognitionApplicationMatch: String, Codable, Sendable {
    case exact, prefix, wordPrefix, substring, abbreviation, typo, unknown
    init(from decoder: Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer(); try container.encode(rawValue)
    }
}
