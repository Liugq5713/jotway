import AppKit
import GRDB
import SwiftUI
import XCTest
@testable import Jotway

@MainActor
final class JevPanelTests: XCTestCase {
    @MainActor
    private final class Classifier {
        struct Call {
            let text: String
        }
        var calls: [Call] = []
        private var replies: [Int: CheckedContinuation<Jev.Decision?, Error>] = [:]

        func recognize(_ text: String) async throws -> Jev.Decision? {
            let index = calls.count
            calls.append(Call(text: text))
            return try await withCheckedThrowingContinuation { replies[index] = $0 }
        }

        func reply(_ index: Int, action: Jev.Action?) throws {
            let continuation = try XCTUnwrap(replies.removeValue(forKey: index))
            continuation.resume(returning: action.map { .init(action: $0, model: "jev-1.13.0") })
        }

        func fail(_ index: Int, error: Error) throws {
            try XCTUnwrap(replies.removeValue(forKey: index)).resume(throwing: error)
        }

        func finish() {
            let pending = Array(replies.values)
            replies.removeAll()
            for continuation in pending { continuation.resume(returning: nil) }
        }
    }

    /// Chrome 走 action executor。本探针记录合成执行正文。
    private actor ActionProbe {
        private(set) var chromeQueries: [String] = []

        func recordChrome(_ url: URL) {
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "q" }?.value ?? url.absoluteString
            chromeQueries.append(query)
        }
    }

    @MainActor
    private final class Opener {
        var urls: [URL] = []
        private var replies: [@MainActor (Result<NSRunningApplication, Error>) -> Void] = []

        func open(_ url: URL, configuration: NSWorkspace.OpenConfiguration,
                  reply: @escaping @MainActor (Result<NSRunningApplication, Error>) -> Void) {
            XCTAssertTrue(configuration.activates)
            XCTAssertFalse(configuration.createsNewApplicationInstance)
            XCTAssertFalse(configuration.allowsRunningApplicationSubstitution)
            XCTAssertFalse(configuration.promptsUserIfNeeded)
            urls.append(url)
            replies.append(reply)
        }

        func reply(_ index: Int, succeeds: Bool) {
            if succeeds { replies[index](.success(.current)) }
            else { replies[index](.failure(NSError(domain: "Jotway.JevPanelTests", code: 1))) }
        }
    }

    @MainActor
    private final class Key {
        var value: String? = "synthetic-test-key"
        var reads = 0
    }

    @MainActor
    private final class ModuleDependencies {
        var notesRun: @MainActor @Sendable (AppleNotes.Request) async throws -> AppleNotes.Response = { _ in
            throw TestFailure.unexpectedNetwork
        }
    }

    @MainActor
    private struct Fixture {
        let suite: String
        let defaults: UserDefaults
        let board: NSPasteboard
        let app: AppState
        let settings: JevSettings
        let controller: PanelController
        let panel: RecordPanel
        let editor: EditorTextView
        let classifier: Classifier
        let opener: Opener
        let actions: ActionProbe
        let repository: LauncherStore
        let secret: Key
        let moduleDependencies: ModuleDependencies
        let notesModule: AppleNotesModule

        func operations() async throws -> OperationSnapshot {
            await app.operationRecorder.flush()
            return try OperationStore(repository: repository).snapshot()
        }

        func close() {
            if editor.hasMarkedText() { editor.unmarkText() }
            classifier.finish()
            panel.close()
            controller.cancelApplicationPreload()
            board.releaseGlobally()
            defaults.removePersistentDomain(forName: suite)
        }
    }

    private enum TestFailure: Error { case timedOut, unexpectedNetwork }

    private func until(_ condition: () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<400 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Jev 面板离屏操作未在 2 秒内结束", file: file, line: line)
        throw TestFailure.timedOut
    }

    private func key(_ modifiers: NSEvent.ModifierFlags = .command, repeated: Bool = false,
                     code: UInt16 = 0x24) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                        windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
                        isARepeat: repeated, keyCode: code)!
    }

    private func fixture(draft: String,
                         applications: [InstalledApplication] = [],
                         failOperationWrite: Bool = false) throws -> Fixture {
        _ = NSApplication.shared
        let suite = "Jotway.JevPanelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let board = NSPasteboard.withUniqueName(), secret = Key(), classifier = Classifier(), opener = Opener()
        let settings = JevSettings(defaults: defaults, readKey: { secret.reads += 1; return secret.value },
            writeKey: { secret.value = $0 }, deleteKey: { secret.value = nil },
            checkConnection: { _ in XCTFail("Must not access the network"); throw TestFailure.unexpectedNetwork })
        let repo = LauncherStore.inMemory()
        if failOperationWrite {
            try repo.dbQueue.write { try $0.execute(sql: "CREATE TRIGGER fail_operation BEFORE INSERT ON operation_events BEGIN SELECT RAISE(FAIL, 'synthetic operation failure'); END") }
        }
        let actions = ActionProbe()
        let moduleDependencies = ModuleDependencies()
        var dependencies = BundledActionDependencies()
        dependencies.notesRun = { try await moduleDependencies.notesRun($0) }
        dependencies.chromeLocate = { URL(fileURLWithPath: "/Applications/Google Chrome.app") }
        dependencies.chromeOpen = { url, _, _ in await actions.recordChrome(url) }
        let modules = BundledActions.modules(preferences: defaults, dependencies: dependencies)
        let notesModule = try XCTUnwrap(modules.compactMap { $0 as? AppleNotesModule }.first)
        let app = AppState(repository: repo, preferences: defaults, actionModules: { _ in modules })
        let session = app.makeLauncherSession(settings: settings, catalog: ApplicationCatalog(applications: applications),
            recognize: { text, _, _ in try await classifier.recognize(text) })
        session.updateInput(draft)
        let controller = PanelController(appState: app, session: session, pasteboard: board,
            openApplication: { url, configuration, reply in opener.open(url, configuration: configuration, reply: reply) })
        let panel = try XCTUnwrap(controller.prewarmRecordPanel())
        panel.contentView?.layoutSubtreeIfNeeded()
        func find(_ view: NSView) -> EditorTextView? {
            (view as? EditorTextView) ?? view.subviews.lazy.compactMap(find).first
        }
        let editor = try XCTUnwrap(panel.contentView.flatMap(find))
        XCTAssertTrue(controller.prepareRecordPanel() === panel)
        panel.contentView?.layoutSubtreeIfNeeded()
        XCTAssertFalse(panel.isVisible)
        return Fixture(suite: suite, defaults: defaults, board: board, app: app, settings: settings,
                       controller: controller, panel: panel, editor: editor, classifier: classifier,
                       opener: opener, actions: actions, repository: repo, secret: secret,
                       moduleDependencies: moduleDependencies, notesModule: notesModule)
    }

    private func application() throws -> (directory: URL, installed: InstalledApplication) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("JotwayJevPanel-\(UUID().uuidString)")
        let url = directory.appendingPathComponent("TestLaunch.app"), contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": "com.jotway.tests.jev-launch", "CFBundleName": "TestLaunch",
                                   "CFBundlePackageType": "APPL", "CFBundleVersion": "1"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        _ = try XCTUnwrap(Bundle(url: url))
        return (directory, InstalledApplication(url: url, name: "TestLaunch", searchNames: ["TestLaunch"]))
    }

    func testReturnAndCommandReturnUseExistingConnectorOnceWithoutPendingConfirmation() async throws {
        // 没有 Jev Key / 建议时，非默认 action 仍可先显式选中，再确认执行；所有确认入口都写本地操作事实。
        do {
            let manual = try fixture(draft: "手动选择搜索")
            defer { manual.close() }
            manual.secret.value = nil
            try await until { manual.controller.session.state.intentCanCycle }
            manual.controller.session.send(.cycleTarget(forward: true))
            XCTAssertEqual(manual.controller.session.state.displayedActionTitle, "Google Search")
            XCTAssertTrue(manual.controller.session.state.intentDeviated)
            manual.app.setActionEnabled(false, for: ChromeModule.moduleDescriptor.id)
            XCTAssertTrue(manual.controller.session.state.intentDeviated)
            XCTAssertTrue(manual.controller.session.state.intentCandidates.contains {
                $0.id == "chrome" && $0.isSelected
            })
            manual.controller.session.send(.selectTarget("chrome"))
            manual.controller.session.send(.confirm(.button))
            let unavailableQueries = await manual.actions.chromeQueries
            XCTAssertTrue(unavailableQueries.isEmpty)
            XCTAssertEqual(manual.controller.session.state.message, "App Unavailable")
            manual.app.setActionEnabled(true, for: ChromeModule.moduleDescriptor.id)
            manual.controller.session.send(.confirm(.button))
            try await until { await manual.actions.chromeQueries.count == 1 }
            let manualFeedback = try await manual.operations()
            XCTAssertEqual(manualFeedback.attempts.count, 1)
            XCTAssertEqual(manualFeedback.attempts.first?.confirmationSource, .button)
            XCTAssertEqual(manualFeedback.attempts.first?.selectionOrigin, .userChoice)
            XCTAssertTrue(manualFeedback.events.contains { $0.kind == .confirmationBlocked })
            XCTAssertEqual(manualFeedback.events.last { $0.kind == .targetSelected }?.targetKind, .action,
                           "已禁用的 action 仍是 action，不能误记成 application")
        }

        // Jev 的 .google 经语义映射走 ChromeAction，fire-and-forget，一次到达。
        let body = "  用 Google 搜索 Swift 6\n保留代码：let a = 1\nhttps://example.invalid/a?b=c  "
        let value = try fixture(draft: body)
        defer { value.close() }
        let editor = value.editor
        _ = try XCTUnwrap(editor.focusTarget)
        try await until { value.classifier.calls.count == 1 }
        XCTAssertEqual(value.controller.session.state.displayedActionTitle, "Set Up Notes")
        value.controller.session.send(.cycleTarget(forward: true))
        XCTAssertTrue(value.controller.session.state.intentDeviated)
        let pendingFeedback = try await value.operations()
        XCTAssertTrue(pendingFeedback.attempts.isEmpty)
        let beforeReply = await value.actions.chromeQueries
        XCTAssertTrue(beforeReply.isEmpty)
        XCTAssertEqual(value.classifier.calls[0].text, body)
        try value.classifier.reply(0, action: .google)
        try await until { value.controller.session.state.intentTitle == "Google Search" && value.controller.session.state.intentStatus == nil }
        XCTAssertTrue(value.controller.session.state.intentDeviated,
                      "迟到建议即使与显式目标相同，也不能清除用户选择")
        let beforeConfirmation = await value.actions.chromeQueries
        XCTAssertTrue(beforeConfirmation.isEmpty)
        XCTAssertEqual(editor.string, body)
        editor.keyDown(with: key([.capsLock, .numericPad], code: 0x4C))
        editor.keyDown(with: key([.numericPad], repeated: true, code: 0x4C))
        value.controller.session.send(.confirm(.button)) // A simultaneous click cannot consume the same suggestion again.
        try await until { await value.actions.chromeQueries.count == 1 }
        let queries = await value.actions.chromeQueries
        XCTAssertEqual(queries.count, 1)
        // 归一后 action 路由用裁剪后的正文（与备忘录同构）；query 解码回裁剪正文。
        XCTAssertEqual(queries[0], body.trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertEqual(value.controller.session.draft.content, "")
        XCTAssertEqual(editor.string, "")
        XCTAssertTrue(value.opener.urls.isEmpty)
        XCTAssertFalse(value.panel.isVisible)
        let entries = try await value.operations()
        XCTAssertEqual(entries.attempts.count, 1)
        let attempt = try XCTUnwrap(entries.attempts.first)
        XCTAssertEqual(entries.inputs.first { $0.id == attempt.inputID }?.text, body)
        XCTAssertEqual(attempt.targetID, "chrome")
        XCTAssertEqual(attempt.routeSource, .explicit)
        XCTAssertEqual(attempt.confirmationSource, .enter)
        XCTAssertNotNil(attempt.firstChoiceEventID)
        XCTAssertNil(attempt.decisionEventID, "离屏准备不能制造实际展示")
        XCTAssertFalse(entries.events.contains { $0.kind == .routePresented || $0.kind == .panelOpened })
        let recognition = try XCTUnwrap(entries.events.first { $0.kind == .recognitionFinished && $0.outcome == .suggested })
        guard case .recognition(let detail) = recognition.details else { return XCTFail("Missing recognition detail") }
        XCTAssertEqual(detail.actualModel, "jev-1.13.0")
        XCTAssertEqual(entries.contexts.first { $0.id == attempt.contextID }?.ruleVersion, Jev.ruleVersion)
        XCTAssertNotNil(recognition.requestID)
    }


    func testRemovedDestinationPhraseFallsBackToNotesWithoutChromeSuggestion() async throws {
        let body = "发给已移除目标整理这份材料"
        let value = try fixture(draft: body)
        defer { value.close() }
        let editor = value.editor
        _ = try XCTUnwrap(editor.focusTarget)
        try await until { value.classifier.calls.count == 1 && value.controller.session.state.intentStatus == "Finding an App…" }

        // ⇧⏎ 永远换行，不再取决于提交方式偏好。
        editor.keyDown(with: key([.shift]))
        XCTAssertTrue(editor.string.contains("\n"))
        XCTAssertEqual(value.controller.session.state.intentTitle, "Set Up Notes")
        let searchesAfterNewline = await value.actions.chromeQueries
        let feedbackAfterNewline = try await value.operations()
        XCTAssertTrue(searchesAfterNewline.isEmpty)
        XCTAssertTrue(feedbackAfterNewline.attempts.isEmpty)

        // ⏎ 永远执行：识别在路上的几百毫秒与落地后行为一致，兜底存到默认 action（备忘录）。
        let notes = NotesRunProbe()
        value.moduleDependencies.notesRun = { await notes.record($0) }
        try value.notesModule.setDestination(.init(id: "folder-1", name: "测试 / Jotway"))
        editor.keyDown(with: key([]))
        try await until { await notes.count == 1 }
        let stored = await notes.first
        XCTAssertTrue(stored?.html?.contains(body) == true)
        let finalSearches = await value.actions.chromeQueries
        XCTAssertTrue(finalSearches.isEmpty, "已移除目标的普通正文不能变成 Chrome 搜索")
    }

    func testEscapePreservesDraftAndTerminationCapturesFinalTextAfterRetention() async throws {
        let body = "这是一条待识别的合成正文"
        let value = try fixture(draft: body)
        defer { value.close() }
        let editor = value.editor
        _ = try XCTUnwrap(editor.focusTarget)
        try await until { value.classifier.calls.count == 1 }
        try value.classifier.reply(0, action: .google)
        try await until { value.controller.session.state.intentTitle == "Google Search" }

        // Esc 不再先关闭建议（✕ 入口已删除）：直接取消，暂存草稿并关闭面板。
        editor.keyDown(with: key([], code: 0x35))
        let stored = value.controller.session.draft
        XCTAssertEqual(stored.content, editor.string)
        XCTAssertEqual(stored.content, body)
        let feedback = try await value.operations()
        let searches = await value.actions.chromeQueries
        XCTAssertTrue(searches.isEmpty)
        XCTAssertTrue(feedback.attempts.isEmpty)

        let finalText = "退出前最后不到三百毫秒的完整正文\n包括换行  "
        editor.insertText(finalText, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        XCTAssertNil(value.controller.prepareForTermination())
        let final = try await value.operations()
        let finalInput = try XCTUnwrap(final.inputs.first { $0.text == finalText })
        XCTAssertTrue(final.events.contains { $0.kind == .inputCaptured && $0.inputID == finalInput.id })
        XCTAssertEqual(final.events.filter { $0.kind == .panelHidden }.count,
                       feedback.events.filter { $0.kind == .panelHidden }.count,
                       "退出强制采样不能伪造隐藏事件")

        let expired = Int64((Date().timeIntervalSince1970 - 2 * 86_400) * 1_000)
        try await value.repository.dbQueue.write { db in
            try db.execute(sql: "UPDATE operation_inputs SET captured_at = ?", arguments: [expired])
            try db.execute(sql: "UPDATE operation_events SET occurred_at = ?", arguments: [expired])
        }
        try await value.app.operationRecorder.setRetention(days: 1)
        await value.app.operationRecorder.flush()
        XCTAssertTrue(value.app.operationRecorder.isRetired(lineageID: finalInput.lineageID))
        let nextText = "过期后再次编辑仍需采集"
        editor.insertText(nextText, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        XCTAssertNil(value.controller.prepareForTermination())
        let renewed = try await value.operations()
        let nextInput = try XCTUnwrap(renewed.inputs.first { $0.text == nextText })
        XCTAssertNotEqual(nextInput.lineageID, finalInput.lineageID)
        XCTAssertFalse(renewed.inputs.contains { $0.lineageID == finalInput.lineageID })
    }

    func testNaturalLanguageApplicationFailureKeepsDraftAndSuccessClearsOnlyItsSnapshot() async throws {
        let local = try application()
        defer { try? FileManager.default.removeItem(at: local.directory) }
        let cases = [(body: " TestLaunch ", succeeds: false, clears: false),
                     (body: "TestLaunch", succeeds: true, clears: true),
                     (body: "  TESTL  ", succeeds: false, clears: false),
                     (body: "TestL", succeeds: true, clears: true),
                     (body: "打开 TestLaunch", succeeds: false, clears: false),
                     (body: "打开 TestLaunch", succeeds: true, clears: true),
                     (body: "打开 TestLaunch\n另外记下明天的会议安排", succeeds: true, clears: false)]
        for test in cases {
            let body = test.body, value = try fixture(draft: test.body, applications: [local.installed])
            defer { value.close() }
            _ = try XCTUnwrap(value.editor.focusTarget)
            value.secret.value = nil // Local names and launch commands do not require the model's key.
            let keyReads = value.secret.reads
            try await until { value.controller.session.state.intentTitle != nil }
            XCTAssertTrue(value.classifier.calls.isEmpty)
            XCTAssertEqual(value.secret.reads, keyReads)
            try await until { value.controller.session.state.intentTitle == "Open “TestLaunch”" }
            value.editor.keyDown(with: key([]))
            value.editor.keyDown(with: key([], repeated: true))
            value.controller.session.send(.confirm(.button))
            XCTAssertEqual(value.opener.urls, [local.installed.url])
            XCTAssertEqual(value.controller.session.draft.content, body, "系统回调前原草稿必须已持久化")
            XCTAssertTrue(value.controller.session.state.isOpeningApplication)
            value.opener.reply(0, succeeds: test.succeeds)
            XCTAssertFalse(value.controller.session.state.isOpeningApplication)
            XCTAssertEqual(value.controller.session.draft.content, test.clears ? "" : body)
            XCTAssertEqual(value.editor.string, test.clears ? "" : body)
            if !test.succeeds {
                XCTAssertNotNil(value.controller.prepareRecordPanel())
                XCTAssertTrue(value.controller.session.state.message?.contains("kept") == true)
                XCTAssertEqual(value.opener.urls.count, 1)
            }
            XCTAssertFalse(value.panel.isVisible)
            let entries = try await value.operations()
            XCTAssertEqual(entries.attempts.count, 1)
            let attempt = try XCTUnwrap(entries.attempts.first)
            XCTAssertEqual(entries.inputs.first { $0.id == attempt.inputID }?.text, body)
            XCTAssertEqual(attempt.targetKind, .application)
            XCTAssertEqual(attempt.routeSource, .localApplication)
            XCTAssertEqual(attempt.confirmationSource, .enter)
            let recognition = try XCTUnwrap(entries.events.first { $0.kind == .recognitionFinished && $0.outcome == .suggested })
            guard case .recognition(let detail) = recognition.details else { return XCTFail("Missing recognition detail") }
            XCTAssertNil(detail.actualModel)
            XCTAssertEqual(detail.candidates.first?.name, "TestLaunch")
            XCTAssertEqual(detail.candidates.first?.match,
                           body.hasPrefix("打开") || body.trimmingCharacters(in: .whitespaces) == "TestLaunch" ? "exact" : "prefix")
            let terminal = try XCTUnwrap(entries.events.first { $0.kind == .executionFinished && $0.attemptID == attempt.id })
            XCTAssertEqual(terminal.outcome, test.succeeds ? .opened : .unknown)
            XCTAssertTrue(entries.events.contains { $0.kind == .submissionAccepted && $0.attemptID == attempt.id })
        }

        for invalidation in ["conflict", "missing"] {
            let value = try fixture(draft: "TestL", applications: [local.installed])
            defer { value.close() }
            _ = try XCTUnwrap(value.editor.focusTarget)
            try await until { value.controller.session.state.intentTitle != nil }
            if invalidation == "conflict" {
                value.controller.session.catalog.replaceApplications([
                    local.installed, .init(url: local.directory.appendingPathComponent("Other.app"),
                    name: "TestLaunch Other", searchNames: [])])
                XCTAssertEqual(value.controller.session.state.intentTitle, "Set Up Notes", "目录新增冲突使旧建议失效并恢复兜底")
            } else {
                try FileManager.default.removeItem(at: local.installed.url)
            }
            var setupOpened = false
            if invalidation == "conflict" {
                // 捕获配置 effect，离屏测试不打开配置窗口或请求系统授权。
                value.controller.session.handleEffect = { effect in
                    if case .showActionSetup(let request) = effect {
                        XCTAssertEqual(request.snapshot.id, "apple-notes")
                        setupOpened = true
                    }
                    return true
                }
            }
            value.editor.keyDown(with: invalidation == "missing" ? key([]) : key())
            XCTAssertEqual(setupOpened, invalidation == "conflict")
            XCTAssertTrue(value.opener.urls.isEmpty, "执行时重验目标与唯一性")
            XCTAssertEqual(value.editor.string, "TestL")
            XCTAssertEqual(value.controller.session.draft.content, "TestL")
            let invalidatedFeedback = try await value.operations()
            XCTAssertTrue(invalidatedFeedback.attempts.isEmpty, "确认前校验失败不能制造执行尝试")
        }
    }

    func testOldApplicationSuccessCannotClearEditedDraftAfterPanelReopens() async throws {
        let local = try application()
        defer { try? FileManager.default.removeItem(at: local.directory) }
        let value = try fixture(draft: "TestL", applications: [local.installed])
        defer { value.close() }
        _ = try XCTUnwrap(value.editor.focusTarget)
        try await until { value.controller.session.state.intentTitle != nil }
        XCTAssertTrue(value.classifier.calls.isEmpty)
        value.editor.keyDown(with: key())
        XCTAssertEqual(value.opener.urls.count, 1)
        XCTAssertTrue(value.controller.prepareRecordPanel() === value.panel)
        value.editor.insertText("后来的独立草稿", replacementRange: NSRange(location: 0, length: value.editor.string.utf16.count))
        value.editor.delegate?.textDidEndEditing?(Notification(name: NSText.didEndEditingNotification, object: value.editor))
        let newer = value.controller.session.draft
        XCTAssertEqual(newer.content, "后来的独立草稿")
        value.controller.session.state.message = "当前草稿提示"
        value.opener.reply(0, succeeds: true)
        XCTAssertEqual(value.editor.string, newer.content)
        XCTAssertEqual(value.controller.session.draft, newer)
        XCTAssertEqual(value.controller.session.state.message, "当前草稿提示")
        XCTAssertEqual(value.opener.urls.count, 1)
        XCTAssertEqual(value.app.applicationUsage[local.installed.url.path]?.openCount, 1)
        XCTAssertFalse(value.panel.isVisible)
        let entries = try await value.operations()
        let attempt = try XCTUnwrap(entries.attempts.first)
        XCTAssertEqual(entries.inputs.first { $0.id == attempt.inputID }?.text, "TestL")
        XCTAssertEqual(entries.events.first { $0.kind == .executionFinished && $0.attemptID == attempt.id }?.outcome, .opened)
    }

    func testFailedSubmissionDoesNotOverwriteNewDraftAndCanBeRestored() async throws {
        let original = "尚未写入的旧提交"
        let value = try fixture(draft: original)
        defer { value.close() }
        let failure = FailingNotesRunProbe()
        value.moduleDependencies.notesRun = { try await failure.run($0) }
        try value.notesModule.setDestination(.init(id: "folder-1", name: "测试 / Jotway"))
        value.controller.session.send(.refreshConfiguration)
        try await until { value.controller.session.state.displayedActionTitle == "Save to Notes" }

        value.controller.session.send(.confirm(.enter))
        try await until { value.controller.session.draft.content.isEmpty }
        XCTAssertNotNil(value.controller.prepareRecordPanel())
        value.controller.session.send(.inputChanged("随后输入的新草稿"))
        try await until { await failure.count == 1 }
        await failure.releaseFailure()
        try await until { value.controller.session.activeSubmissionCount == 0 }

        XCTAssertEqual(value.controller.session.draft.content, "随后输入的新草稿")
        XCTAssertEqual(value.controller.session.failedSubmission?.draft.content, original)
        XCTAssertTrue(value.controller.session.state.hasFailedSubmission)

        value.controller.session.send(.restoreFailedSubmission)
        XCTAssertEqual(value.controller.session.draft.content, "随后输入的新草稿\n\n\(original)")
        XCTAssertNil(value.controller.session.failedSubmission)
        XCTAssertFalse(value.controller.session.state.hasFailedSubmission)
        let merged = try await value.operations()
        let originalAttempt = try XCTUnwrap(merged.attempts.first)
        let originalInput = try XCTUnwrap(merged.inputs.first { $0.id == originalAttempt.inputID })
        let restored = try XCTUnwrap(merged.events.first { $0.kind == .draftRestored })
        let mergedInput = try XCTUnwrap(merged.inputs.first { $0.id == restored.inputID })
        XCTAssertEqual(mergedInput.text, "随后输入的新草稿\n\n\(original)")
        XCTAssertNotEqual(mergedInput.lineageID, originalInput.lineageID)
        guard case .restoration(let detail) = restored.details else { return XCTFail("Missing restoration detail") }
        XCTAssertEqual(detail.mode, .merge)
        XCTAssertEqual(detail.sourceLineageID, originalInput.lineageID)
        XCTAssertEqual(detail.sourceAttemptID, originalAttempt.id)

        // Failure into an empty editor reuses the exact input. A later clear invalidates its callback.
        let retry = try fixture(draft: original)
        defer { retry.close() }
        let retryFailure = FailingNotesRunProbe()
        retry.moduleDependencies.notesRun = { try await retryFailure.run($0) }
        try retry.notesModule.setDestination(.init(id: "folder-1", name: "测试 / Jotway"))
        let nativeEffect = retry.controller.session.handleEffect
        retry.controller.session.handleEffect = { effect in
            if case .showPanel = effect { return true } // Keep this existing test entirely offscreen.
            return nativeEffect(effect)
        }
        retry.controller.session.send(.refreshConfiguration)
        retry.controller.session.send(.selectTarget("apple-notes"))
        retry.controller.session.send(.confirm(.enter))
        try await until { await retryFailure.count == 1 }
        await retryFailure.releaseFailure()
        try await until { retry.controller.session.activeSubmissionCount == 0 }
        XCTAssertEqual(retry.controller.session.draft.content, original)
        retry.controller.session.send(.panelPresented)
        retry.controller.session.send(.selectTarget("apple-notes"))
        retry.controller.session.send(.confirm(.button))
        try await until { await retryFailure.count == 2 }
        let retried = try await retry.operations()
        XCTAssertEqual(retried.attempts.count, 2)
        let first = try XCTUnwrap(retried.attempts.first { $0.retryOfAttemptID == nil })
        let second = try XCTUnwrap(retried.attempts.first { $0.retryOfAttemptID == first.id })
        XCTAssertEqual(first.inputID, second.inputID)
        XCTAssertNotNil(first.firstChoiceEventID)
        XCTAssertEqual(first.firstChoiceEventID, second.firstChoiceEventID)
        let retryStatus = await retry.app.operationRecorder.status()
        XCTAssertEqual(retryStatus.integrity, .complete)
        try await retry.app.operationRecorder.clear()
        await retryFailure.releaseFailure()
        try await until { retry.controller.session.activeSubmissionCount == 0 }
        let afterClear = try await retry.operations()
        XCTAssertTrue(afterClear.inputs.isEmpty)
        XCTAssertTrue(afterClear.events.isEmpty, "旧执行的回调与失败恢复不能使已清空的数据复活")
    }

    func testQuietStatusAndLocalPrefixConfirmationRenderOffscreenWithoutBlockingSubmission() async throws {
        let local = try application()
        defer { try? FileManager.default.removeItem(at: local.directory) }
        let value = try fixture(draft: "一条普通的合成记录", applications: [local.installed])
        defer { value.close() }
        _ = try XCTUnwrap(value.editor.focusTarget)
        let root = try XCTUnwrap(value.panel.contentView)
        func edit(_ text: String) {
            value.editor.insertText(text, replacementRange: NSRange(location: 0, length: value.editor.string.utf16.count))
        }
        func preview(_ name: String) async throws {
            try await Task.sleep(for: .milliseconds(30))
            root.layoutSubtreeIfNeeded()
            if let directory = ProcessInfo.processInfo.environment["JOTWAY_JEV_PREVIEW_DIR"] {
                func host(_ view: NSView) -> NSView? {
                    (view as? NSHostingView<EditorView>) ?? view.subviews.lazy.compactMap(host).first
                }
                let view = try XCTUnwrap(host(root))
                let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    .write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
            }
            XCTAssertFalse(value.panel.isVisible)
        }
        try await until { value.classifier.calls.count == 1 }
        try value.classifier.reply(0, action: nil)
        try await until { value.controller.session.state.intentStatus == nil }
        XCTAssertEqual(value.controller.session.state.intentTitle, "Set Up Notes"); XCTAssertNil(value.controller.session.state.intentIssue)
        try await preview("no-suggestion")

        edit("第二条合成记录")
        try await until { value.classifier.calls.count == 2 }
        try value.classifier.fail(1, error: Jev.Failure.invalidResponse)
        try await until { value.controller.session.state.intentIssue != nil }
        XCTAssertNil(value.controller.session.state.intentStatus); XCTAssertEqual(value.controller.session.state.intentTitle, "Set Up Notes")
        XCTAssertEqual(value.controller.session.state.intentIssue, "Couldn't read Jev's reply. Try again later.")
        try await preview("request-error")
        value.panel.setContentSize(NSSize(width: 360, height: 160))
        try await preview("request-error-compact")
        value.panel.setContentSize(NSSize(width: 560, height: 160))

        edit("TestL")
        XCTAssertNil(value.controller.session.state.intentIssue)
        try await until { value.controller.session.state.intentTitle == "Open “TestLaunch”" }
        XCTAssertEqual(value.classifier.calls.count, 2)
        try await preview("prefix-suggestion")
        value.panel.setContentSize(NSSize(width: 360, height: 160))
        try await preview("prefix-suggestion-compact")
        value.editor.keyDown(with: key([.shift]))
        XCTAssertEqual(value.editor.string, "TestL\n")
        XCTAssertEqual(value.controller.session.state.intentTitle, "Set Up Notes")
        XCTAssertTrue(value.opener.urls.isEmpty)
        edit("TestL")
        try await until { value.controller.session.state.intentTitle == "Open “TestLaunch”" }
        value.controller.session.send(.compositionChanged(true))
        value.editor.keyDown(with: key())
        // IME 组词期间动作行冻结保持上次解析结果（避免中文输入逐键闪烁），
        // 但 Enter 不穿透、不产生任何提交。
        XCTAssertEqual(value.controller.session.state.intentTitle, "Open “TestLaunch”")
        XCTAssertNil(value.controller.session.state.intentIssue)
        XCTAssertTrue(value.opener.urls.isEmpty)
        value.controller.session.send(.compositionChanged(false))
        try await until { value.controller.session.state.intentTitle != nil }
        value.controller.session.send(.confirm(.button))
        value.controller.session.send(.confirm(.button))
        XCTAssertEqual(value.opener.urls.count, 1)
        value.opener.reply(0, succeeds: false)
        let entries = try await value.operations()
        XCTAssertEqual(entries.attempts.count, 1)
        XCTAssertEqual(entries.attempts.first?.confirmationSource, .button)
        XCTAssertTrue(entries.events.contains { $0.kind == .confirmationBlocked && $0.reasonCode == "composition_active" })

        XCTAssertNotNil(value.controller.prepareRecordPanel())
        edit("可以继续提交的合成记录")
        try await until { value.classifier.calls.count == 3 }
        try value.classifier.fail(2, error: Jev.Failure.timeout)
        try await until { value.controller.session.state.intentIssue != nil }
        // 主路由：识别失败后普通 Enter 兜底存到默认 action（备忘录），不落进收件箱。
        let notes = NotesRunProbe()
        value.moduleDependencies.notesRun = { await notes.record($0) }
        try value.notesModule.setDestination(.init(id: "folder-1", name: "测试 / Jotway"))
        value.editor.keyDown(with: key([]))
        try await until { await notes.count == 1 }
        let stored = await notes.first
        XCTAssertTrue(stored?.html?.contains("可以继续提交的合成记录") == true)
        XCTAssertNil(value.controller.session.state.intentIssue)
        XCTAssertEqual(value.opener.urls.count, 1)
    }

    func testEveryConfirmationSourceRecordsAttemptAndStorageFailureDoesNotBlockSearchAction() async throws {
        // Chrome fire-and-forget，一次到达即结束。
        // 三种确认均冻结入口；操作记录写入失败不能阻塞执行。
        let cases: [(IntentRecognition.ConfirmationSource, Bool)] = [
            (.enter, false), (.commandEnter, false),
            (.button, false), (.commandEnter, true),
        ]
        for (trigger, failWrite) in cases {
            let body = "  合成完整正文\n保留空白和第二行  "
            let value = try fixture(draft: body, failOperationWrite: failWrite)
            defer { value.close() }
            _ = try XCTUnwrap(value.editor.focusTarget)
            try await until { value.classifier.calls.count == 1 }
            try value.classifier.reply(0, action: .google)
            try await until { value.controller.session.state.intentTitle == "Google Search" }
            switch trigger {
            case .enter: value.editor.keyDown(with: key([]))
            case .commandEnter: value.editor.keyDown(with: key())
            case .button: value.controller.session.send(.confirm(.button))
            }
            try await until { await value.actions.chromeQueries.count == 1 }
            let executed = await value.actions.chromeQueries
            XCTAssertEqual(executed.count, 1)
            let entries = try await value.operations()
            if failWrite {
                XCTAssertTrue(entries.attempts.isEmpty)
                let status = await value.app.operationRecorder.status()
                XCTAssertEqual(status.integrity, .incomplete)
            } else {
                XCTAssertEqual(entries.attempts.count, 1)
                let attempt = try XCTUnwrap(entries.attempts.first)
                XCTAssertEqual(entries.inputs.first { $0.id == attempt.inputID }?.text, body)
                XCTAssertEqual(attempt.targetID, "chrome")
                XCTAssertEqual(attempt.routeSource, .model)
                let expected: OperationConfirmationSource = switch trigger {
                case .enter: .enter
                case .commandEnter: .commandEnter
                case .button: .button
                }
                XCTAssertEqual(attempt.confirmationSource, expected)
                let status = await value.app.operationRecorder.status()
                XCTAssertEqual(status.integrity, .complete)
            }
            XCTAssertTrue(value.opener.urls.isEmpty)
            XCTAssertFalse(value.panel.isVisible)
        }
    }
}

/// 启动器主路由测试用：拦截备忘录写入，回执成功。
private actor NotesRunProbe {
    private(set) var requests: [AppleNotes.Request] = []
    var count: Int { requests.count }
    var first: AppleNotes.Request? { requests.first }
    func record(_ request: AppleNotes.Request) -> AppleNotes.Response {
        requests.append(request)
        return .init(version: 1, requestID: request.requestID, status: "ok",
                     noteID: "note-\(requests.count)", folderID: request.folderID)
    }
}

private actor FailingNotesRunProbe {
    private(set) var count = 0
    private var continuation: CheckedContinuation<Void, Never>?

    func run(_ request: AppleNotes.Request) async throws -> AppleNotes.Response {
        count += 1
        await withCheckedContinuation { continuation = $0 }
        throw NSError(domain: "JotwayTests.SyntheticNotesFailure", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "合成写入失败"])
    }

    func releaseFailure() {
        continuation?.resume()
        continuation = nil
    }
}
