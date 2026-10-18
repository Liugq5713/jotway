import Foundation
import Observation

/// Account snapshots have a separate lifetime from model bindings and draft generation.
@MainActor @Observable
final class HostedAIState {
    enum Status: Equatable { case unverified, active, noCredits, invalid, disabled, unavailable }
    struct Credentials {
        let load: @MainActor () throws -> String?
        let save: @MainActor (String) throws -> Void
        let remove: @MainActor () throws -> Void
        static var local: Self {
            .init(load: { try ActivationCodeStore.shared.load() },
                  save: { try ActivationCodeStore.shared.save($0) },
                  remove: { try ActivationCodeStore.shared.remove() })
        }
    }
    private(set) var account: HostedAI.Account?
    private(set) var status: Status = .unverified
    private(set) var problem: HostedAI.Problem?
    private(set) var isRefreshing = false
    private(set) var credentialRevision = 0
    @ObservationIgnored private let credentials: Credentials
    @ObservationIgnored private let fetchAccount: @Sendable (String) async throws -> HostedAI.Account
    @ObservationIgnored private var activationSequence = 0
    @ObservationIgnored private var readSequence = 0
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var credentialPresence: Bool?

    init(credentials: Credentials = .local,
         fetchAccount: @escaping @Sendable (String) async throws -> HostedAI.Account = { try await HostedAI.account(code: $0) }) {
        self.credentials = credentials; self.fetchAccount = fetchAccount
    }
    isolated deinit { refreshTask?.cancel() }

    var hasCode: Bool {
        _ = credentialRevision
        if let credentialPresence { return credentialPresence }
        // An unreadable hosted credential must never silently route to a personal account.
        let present: Bool
        do { present = try credentials.load() != nil }
        catch { present = true }
        credentialPresence = present
        return present
    }

    func loadCode() throws -> String? { try credentials.load() }

    /// A failed replacement never changes the previously stored code or its account state.
    func activate(_ rawCode: String) async throws -> Int {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard HostedAI.validCode(code) else { throw HostedAI.failure(status: 401) }
        activationSequence &+= 1
        let sequence = activationSequence
        let value = try await fetchAccount(code)
        try Task.checkCancellation()
        guard sequence == activationSequence else { throw CancellationError() }
        guard !value.disabled else { throw HostedAI.failure(status: 403) }
        try credentials.save(code)
        credentialPresence = true
        cancelRefresh()
        credentialRevision &+= 1
        adopt(value)
        return credentialRevision
    }

    func remove() throws {
        try credentials.remove()
        credentialPresence = false
        activationSequence &+= 1; credentialRevision &+= 1
        cancelRefresh()
        account = nil; problem = nil; status = .unverified
    }

    func refresh() async {
        let (sequence, task) = beginRefresh()
        await withTaskCancellationHandler { await task.value } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.readSequence == sequence else { return }
                self?.cancelRefresh()
            }
        }
    }

    /// Called once after an actual hosted request, even when its caller was cancelled.
    /// The new unstructured metadata read does not inherit the caller's cancellation.
    func finishedCall(credentialRevision revision: Int, problem failure: HostedAI.Problem?) {
        guard revision == credentialRevision, hasCode else { return }
        if let failure { reject(failure) }
        _ = beginRefresh(preserving: failure == .insufficientQuota ? failure : nil)
    }

    private func beginRefresh(preserving failure: HostedAI.Problem? = nil) -> (Int, Task<Void, Never>) {
        cancelRefresh()
        let sequence = readSequence
        let revision = credentialRevision
        let code: String?
        do { code = try credentials.load() }
        catch {
            reject(.unavailable)
            return (sequence, Task {})
        }
        guard let code else { return (sequence, Task {}) }
        isRefreshing = true
        let fetch = fetchAccount
        let task = Task { @MainActor [weak self] in
            do {
                let value = try await fetch(code)
                guard let self, !Task.isCancelled, sequence == self.readSequence,
                      revision == self.credentialRevision else { return }
                if value.disabled { self.reject(.disabled) }
                else {
                    self.adopt(value)
                    if let failure { self.reject(failure) }
                }
            } catch {
                guard let self, !Task.isCancelled, sequence == self.readSequence,
                      revision == self.credentialRevision else { return }
                self.reject(HostedAI.problem(error) ?? .unavailable)
            }
            guard let self, sequence == self.readSequence else { return }
            self.isRefreshing = false; self.refreshTask = nil
        }
        refreshTask = task
        return (sequence, task)
    }

    private func cancelRefresh() {
        readSequence &+= 1
        refreshTask?.cancel(); refreshTask = nil; isRefreshing = false
    }
    private func adopt(_ value: HostedAI.Account) {
        account = value
        problem = value.quota.available == 0 ? .insufficientQuota : nil
        status = value.quota.available == 0 ? .noCredits : .active
    }
    private func reject(_ failure: HostedAI.Problem) {
        if failure != .invalid && failure != .disabled, status == .invalid || status == .disabled { return }
        problem = failure
        switch failure {
        case .invalid: account = nil; status = .invalid
        case .disabled: account = nil; status = .disabled
        case .insufficientQuota: status = .noCredits
        default:
            // A later connectivity failure cannot restore a previously rejected account.
            if status != .invalid && status != .disabled { status = .unavailable }
        }
    }
}
