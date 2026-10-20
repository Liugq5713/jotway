import AppKit
@preconcurrency import ApplicationServices
import Observation

/// 检查开始时取序号；跨执行器迟到的结果不能覆盖更新的检查。
struct SelectedTextPermissionObservation: Sendable {
    let startedAt: ContinuousClock.Instant
    let granted: Bool
}

@MainActor @Observable
final class SelectedTextPermission {
    static let shared = SelectedTextPermission()
    static let didGrantNotification = Notification.Name("Jotway.SelectedTextPermission.didGrant")
    private(set) var granted = false
    private(set) var checking = false
    private var didShowNotice = false
    private var latestCheck: ContinuousClock.Instant?
    private var refreshTask: Task<Void, Never>?
    private var refreshID = UUID()
    private let check: () -> Bool
    private let request: () -> Void

    init(check: @escaping () -> Bool = { AXIsProcessTrusted() },
         request: @escaping () -> Void = {
             _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
         }) {
        self.check = check; self.request = request
    }

    isolated deinit { refreshTask?.cancel() }

    /// 不请求授权、不读取选区；每次刷新最多三秒，替换上一轮。
    func refresh() {
        cancelRefresh()
        checkNow()
        guard !granted else { return }
        checking = true
        let id = refreshID
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(250)) }
                catch { return }
                guard let self, self.refreshID == id else { return }
                guard ContinuousClock.now < deadline else {
                    self.cancelRefresh()
                    return
                }
                self.checkNow()
                if self.granted { return }
            }
        }
    }

    func cancelRefresh() {
        refreshID = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        checking = false
    }

    private func checkNow() {
        let startedAt = ContinuousClock.now
        observe(.init(startedAt: startedAt, granted: check()))
    }

    /// 捕获独立检查后在 MainActor 发布；能力错误不进入此入口。
    @discardableResult
    func observe(_ observation: SelectedTextPermissionObservation) -> Bool {
        guard latestCheck.map({ observation.startedAt >= $0 }) ?? true else { return false }
        latestCheck = observation.startedAt
        granted = observation.granted
        if granted {
            cancelRefresh()
            didShowNotice = false
            NotificationCenter.default.post(name: Self.didGrantNotification, object: self)
        }
        return true
    }

    func requestAccess() { request(); refresh() }

    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func takeNotice(existingMessage: String?) -> String? {
        checkNow()
        guard !granted, !didShowNotice, existingMessage == nil else { return nil }
        didShowNotice = true
        return L10n.text("selected_text.notice")
    }
}
