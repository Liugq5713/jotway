import Foundation

/// The activation code uses Jotway's restricted local credential files, never the Keychain or logs.
@MainActor
final class ActivationCodeStore {
    static let shared = ActivationCodeStore()

    func load() throws -> String? {
        guard let code = try APIKeyStore.shared.load(for: .hostedAIActivation) else { return nil }
        guard HostedAI.validCode(code) else { throw APIKeyStore.Failure.corrupt }
        return code
    }

    func save(_ code: String) throws {
        guard HostedAI.validCode(code) else { throw HostedAI.failure(status: 401) }
        try APIKeyStore.shared.save(code, for: .hostedAIActivation)
    }

    func remove() throws {
        try APIKeyStore.shared.remove(for: .hostedAIActivation)
    }
}
