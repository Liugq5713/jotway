import XCTest
import AppKit
import GRDB
@testable import Jotway

/// 主路径冒烟测试：覆盖仓库、编辑器与面板的核心链路；内存库，随测随弃。
final class MainPathTests: XCTestCase {
    private var repo: LauncherStore!

    override func setUp() {
        super.setUp()
        repo = LauncherStore.inMemory()
    }

    /// 编辑器只保存纯文字；Markdown 与图片语法均为普通字符。
    @MainActor
    func testEditorPlainTextRoundTrip() {
        let textView = EditorTextView(usingTextLayoutManager: true)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.setPlainText("# 标题\n- [ ] 待办\n前文 ![](img1) 后文")
        XCTAssertEqual(textView.string, "# 标题\n- [ ] 待办\n前文 ![](img1) 后文")

        // 全空与纯文本形态
        textView.setPlainText("")
        XCTAssertEqual(textView.string, "")
        textView.setPlainText("纯文本\n两行")
        XCTAssertEqual(textView.string, "纯文本\n两行")

        // 同步同一正文不移动选区。
        textView.setSelectedRange(NSRange(location: 1, length: 2))
        XCTAssertTrue(textView.setPlainText(textView.string))
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 1, length: 2))

        // 混合内容优先文字；富文本去样式；纯图片与文件均忽略。
        let mixed = NSPasteboard.withUniqueName()
        defer { mixed.releaseGlobally() }
        mixed.declareTypes([.string, .tiff], owner: nil)
        mixed.setString("混合文字", forType: .string)
        mixed.setData(Data([0]), forType: .tiff)
        textView.selectAll(nil)
        XCTAssertTrue(textView.insertPlainText(from: mixed))
        XCTAssertEqual(textView.string, "混合文字")

        let rich = NSPasteboard.withUniqueName()
        defer { rich.releaseGlobally() }
        rich.declareTypes([.rtf], owner: nil)
        let styled = NSAttributedString(string: "富文本", attributes: [.font: NSFont.boldSystemFont(ofSize: 24)])
        rich.setData(styled.rtf(from: NSRange(location: 0, length: styled.length), documentAttributes: [:])!, forType: .rtf)
        textView.selectAll(nil)
        XCTAssertTrue(textView.insertPlainText(from: rich))
        XCTAssertEqual(textView.string, "富文本")
        XCTAssertNil(textView.textStorage?.attribute(.attachment, at: 0, effectiveRange: nil))
        let pastedFont = textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertFalse(pastedFont?.fontDescriptor.symbolicTraits.contains(.bold) == true)

        let image = NSPasteboard.withUniqueName()
        defer { image.releaseGlobally() }
        image.declareTypes([.tiff], owner: nil)
        image.setData(Data([0]), forType: .tiff)
        let selectionBeforeImage = textView.selectedRange()
        XCTAssertFalse(textView.insertPlainText(from: image))
        XCTAssertEqual(textView.string, "富文本")
        XCTAssertEqual(textView.selectedRange(), selectionBeforeImage)

        let attachment = NSPasteboard.withUniqueName()
        defer { attachment.releaseGlobally() }
        attachment.declareTypes([.rtfd], owner: nil)
        let wrapper = FileWrapper(regularFileWithContents: Data([0]))
        wrapper.preferredFilename = "image.png"
        let attachmentOnly = NSAttributedString(attachment: NSTextAttachment(fileWrapper: wrapper))
        attachment.setData(attachmentOnly.rtfd(from: NSRange(location: 0, length: attachmentOnly.length),
            documentAttributes: [:])!, forType: .rtfd)
        textView.setSelectedRange(NSRange(location: 0, length: 1))
        let selectionBeforeAttachment = textView.selectedRange()
        XCTAssertFalse(textView.insertPlainText(from: attachment))
        XCTAssertEqual(textView.string, "富文本")
        XCTAssertEqual(textView.selectedRange(), selectionBeforeAttachment)

        let file = NSPasteboard.withUniqueName()
        defer { file.releaseGlobally() }
        file.declareTypes([.fileURL, .string], owner: nil)
        file.setString("file:///tmp/image.png", forType: .fileURL)
        file.setString("/tmp/image.png", forType: .string)
        XCTAssertFalse(textView.insertPlainText(from: file))
        XCTAssertEqual(textView.string, "富文本")

        let longText = String(repeating: "纯文字段落\n", count: 2_000)
        XCTAssertTrue(textView.setPlainText(longText))
        XCTAssertEqual(textView.string, longText)
    }

    func testDatabaseInitializationPreservesLauncherDataAcrossReopen() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Jotway-Database-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("jotway.sqlite").path
        let queue = try DatabaseQueue(path: path)
        try Database.migrate(queue)
        let tables = try queue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
        }
        XCTAssertEqual(Set(tables), ["grdb_migrations", "application_usage", "intent_feedback", "intent_corrections"])
        let store = LauncherStore(dbQueue: queue)
        let feedback = IntentFeedback(id: UUID(), acceptedAt: Date(timeIntervalSince1970: 1_800_000_001),
            draftID: UUID(), draftRevision: 2, text: "保留的反馈", action: .google, targetID: "chrome",
            applicationBundleID: nil, applicationName: nil,
            recognition: .init(source: .model, requestID: UUID(), ruleVersion: Jev.ruleVersion, actualModel: "jev-1.13.0"),
            confirmationSource: .enter, label: .userAccepted)
        let correction = IntentCorrection(text: "保留的纠正", jevTargetID: "chrome", jevLabel: "Google 搜索",
            chosenTargetID: "apple-notes", chosenLabel: "存到备忘录")
        XCTAssertTrue(try store.saveIntentFeedback(feedback))
        XCTAssertTrue(try store.saveIntentCorrection(correction))
        _ = try store.recordApplicationOpens([ApplicationUsage(path: "/Applications/ExampleApp.app",
            openCount: 3, lastOpenedAt: Date(timeIntervalSince1970: 1_800_000_000))])
        try queue.close()

        let reopened = try DatabaseQueue(path: path)
        defer { try? reopened.close() }
        try Database.migrate(reopened)
        try Database.migrate(reopened)
        let reopenedStore = LauncherStore(dbQueue: reopened)
        XCTAssertEqual(try reopenedStore.applicationUsage()["/Applications/ExampleApp.app"]?.openCount, 3)
        XCTAssertEqual(try reopenedStore.intentFeedback(id: feedback.id)?.sample, feedback)
        XCTAssertEqual(try reopenedStore.recentIntentCorrections(), [correction])
    }

}

@MainActor
extension MainPathTests {
    func testRemovedActionPreferencesAndRulesAreCleanedAtLaunch() throws {
        let suite = "JotwayTests.RemovedAction.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set(false, forKey: "actionEnabled.removed-action")
        preferences.set(false, forKey: "actionEnabled.chrome")
        preferences.set(false, forKey: "actionEnabled.apple-notes")
        preferences.set("保留", forKey: "example.actionEnabled.removed-action")
        let rules = [IntentRule(phrase: "旧目标", actionID: "removed-action"),
                     IntentRule(phrase: "搜一下", actionID: "chrome")]
        preferences.set(try JSONEncoder().encode(rules), forKey: "intentRules")

        let state = AppState(repository: .inMemory(), preferences: preferences)

        XCTAssertNil(preferences.object(forKey: "actionEnabled.removed-action"))
        XCTAssertEqual(preferences.string(forKey: "example.actionEnabled.removed-action"), "保留")
        XCTAssertFalse(preferences.bool(forKey: "actionEnabled.chrome"), "已注册但关闭的 action 配置必须保留")
        XCTAssertFalse(preferences.bool(forKey: "actionEnabled.apple-notes"), "已注册但暂不可用的 action 配置必须保留")
        XCTAssertEqual(state.intentRules.map(\.actionID), ["chrome"])
        let stored = try XCTUnwrap(preferences.data(forKey: "intentRules"))
        XCTAssertEqual(try JSONDecoder().decode([IntentRule].self, from: stored).map(\.actionID), ["chrome"])
        XCTAssertEqual(Set(state.actionRegistry.allDescriptors.map(\.id)),
                       ["apple-notes", "apple-reminders", "apple-calendar", "chrome", "chatgpt"])
        XCTAssertFalse(state.actionRegistry.isEnabled("chrome"))
    }

    private func returnEvent(code: UInt16 = 0x24, modifiers: NSEvent.ModifierFlags = [], repeatKey: Bool = false) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: 0, windowNumber: 0, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: repeatKey, keyCode: code)!
    }

    func testReturnAlwaysSubmitsAndShiftReturnNewlines() {
        let editor = EditorTextView()
        let target = EditorFocusTarget()
        let state = LauncherViewState()
        target.textView = editor
        editor.focusTarget = target
        editor.state = state
        state.isIntentRecognitionEnabled = true
        var saves = 0
        editor.send = { if case .confirm(.enter) = $0 { saves += 1 } }
        for code: UInt16 in [0x24, 0x4C] {
            editor.string = "- 牛奶"
            editor.setSelectedRange(NSRange(location: 4, length: 0))
            var before = saves
            // ⏎ 永远执行（不区分单行 / 多行，不再有提交方式偏好）。
            editor.keyDown(with: returnEvent(code: code, modifiers: [.capsLock, .numericPad]))
            XCTAssertEqual(saves, before + 1)
            XCTAssertEqual(editor.string, "- 牛奶")
            editor.string = "- 牛奶"
            editor.setSelectedRange(NSRange(location: 4, length: 0))
            before = saves
            // ⇧⏎ 永远换行。
            editor.keyDown(with: returnEvent(code: code, modifiers: [.capsLock, .numericPad, .shift]))
            XCTAssertEqual(saves, before)
            XCTAssertEqual(editor.string, "- 牛奶\n")
            for extra: NSEvent.ModifierFlags in [.command, .option, .control, [.command, .shift]] {
                let baseline = saves
                editor.keyDown(with: returnEvent(code: code, modifiers: extra))
                XCTAssertEqual(saves, baseline)
            }
        }
        let before = saves
        editor.keyDown(with: returnEvent(modifiers: [], repeatKey: true))
        XCTAssertEqual(saves, before)
    }

    func testMarkedTextReturnDoesNotSubmit() {
        let editor = EditorTextView()
        let target = EditorFocusTarget()
        let state = LauncherViewState()
        target.textView = editor
        editor.focusTarget = target
        editor.state = state
        state.isIntentRecognitionEnabled = true
        var saves = 0
        editor.send = { if case .confirm(.enter) = $0 { saves += 1 } }
        for modifiers: NSEvent.ModifierFlags in [[], .shift] {
            editor.setMarkedText("拼", selectedRange: NSRange(location: 1, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: 0))
            XCTAssertTrue(editor.hasMarkedText())
            editor.keyDown(with: returnEvent(modifiers: modifiers))
            XCTAssertEqual(saves, 0)
            editor.unmarkText()
        }
    }

    /// 使用生产的准备与回调路径，窗口始终隐藏；不占用用户的焦点或全局剪贴板。
    private func withPreparedRecordEditor(
        repository: LauncherStore? = nil,
        draft: String = "",
        applications: [InstalledApplication] = [],
        submissionEffect: SubmissionEffect = .wind,
        firstUseInstallation: Bool = false,
        actionModules: (@MainActor (UserDefaults) -> [any ActionModule])? = nil,
        openApplication: @escaping @MainActor (URL, NSWorkspace.OpenConfiguration, @escaping @MainActor (Result<NSRunningApplication, Error>) -> Void) -> Void = { _, _, _ in
            XCTFail("此测试不应请求打开应用")
        },
        _ body: @MainActor (PanelController, RecordPanel, EditorTextView, AppState, NSPasteboard) async throws -> Void
    ) async throws {
        _ = NSApplication.shared
        if NSImage(named: "JotwayMenuBarTemplate") == nil {
            let asset = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent("Resources/JotwayMenuBarTemplate.pdf")
            let icon = try XCTUnwrap(NSImage(contentsOf: asset))
            XCTAssertTrue(icon.setName("JotwayMenuBarTemplate"))
        }
        let suite = "JotwayTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        let board = NSPasteboard.withUniqueName()
        defer { preferences.removePersistentDomain(forName: suite); board.releaseGlobally() }
        if !firstUseInstallation { preferences.set(submissionEffect.rawValue, forKey: "submissionEffect") }
        let state = AppState(repository: repository ?? repo, preferences: preferences,
                             actionModules: actionModules)
        let session = state.makeLauncherSession(catalog: ApplicationCatalog(applications: applications))
        session.updateInput(draft)
        let controller = PanelController(appState: state, session: session, pasteboard: board, openApplication: openApplication)
        let warmed = try XCTUnwrap(controller.prewarmRecordPanel())
        XCTAssertFalse(warmed.isVisible)
        let panel = try XCTUnwrap(controller.prepareRecordPanel())
        XCTAssertTrue(panel === warmed)
        defer { panel.close() }
        panel.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(20))
        let editor = try XCTUnwrap(panel.contentView.flatMap { findEditor($0) })
        panel.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        XCTAssertFalse(panel.isVisible)
        try await body(controller, panel, editor, state, board)
        XCTAssertFalse(panel.isVisible)
    }

    private func findEditor(_ view: NSView) -> EditorTextView? {
        if let editor = view as? EditorTextView { return editor }
        return view.subviews.lazy.compactMap { self.findEditor($0) }.first
    }

    private func applicationForTesting() throws -> (directory: URL, application: InstalledApplication) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("JotwayMainPath-\(UUID().uuidString)")
        let url = directory.appendingPathComponent("TestLaunch.app")
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.jotway.tests.main-path-launch",
            "CFBundleName": "TestLaunch",
            "CFBundlePackageType": "APPL",
            "CFBundleVersion": "1",
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        _ = try XCTUnwrap(Bundle(url: url))
        return (directory, InstalledApplication(url: url, name: "TestLaunch", searchNames: ["TestLaunch"]))
    }

    private func until(_ condition: () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<150 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("条件未在时限内满足", file: file, line: line)
    }

    func testSlashInputUsesOrdinaryRoutingAndApplicationLaunchReceiptsStayIdempotent() async throws {
        let local = try applicationForTesting()
        defer { try? FileManager.default.removeItem(at: local.directory) }
        var attempts: [URL] = []
        var completion: (@MainActor (Result<NSRunningApplication, Error>) -> Void)?
        var inspectBeforeOpen: (() -> Void)?
        let notes = MainPathNotesProbe()
        var dependencies = BundledActionDependencies()
        dependencies.notesRun = { await notes.record($0) }
        try await withPreparedRecordEditor(draft: "/TestLaunch", applications: [local.application],
            actionModules: { preferences in
                let modules = BundledActions.modules(preferences: preferences, dependencies: dependencies)
                let notesModule = modules.compactMap { $0 as? AppleNotesModule }.first!
                try! notesModule.setDestination(.init(id: "folder-1", name: "测试 / Jotway"))
                return modules
            }, openApplication: { url, configuration, reply in
            inspectBeforeOpen?()
            XCTAssertTrue(configuration.activates)
            XCTAssertFalse(configuration.createsNewApplicationInstance)
            XCTAssertFalse(configuration.allowsRunningApplicationSubstitution)
            XCTAssertFalse(configuration.promptsUserIfNeeded)
            attempts.append(url)
            completion = reply
        }) { controller, panel, editor, state, _ in
            _ = try XCTUnwrap(editor.focusTarget)
            controller.session.send(.refreshConfiguration)
            XCTAssertEqual(controller.session.state.displayedActionTitle, "Save to Notes")
            XCTAssertEqual(controller.session.draft.content, "/TestLaunch")

            editor.insertText("x", replacementRange: editor.selectedRange())
            XCTAssertTrue(editor.undoManager?.canUndo == true)
            XCTAssertTrue(editor.setPlainText("/TestLaunch", reason: .newDraft))
            editor.undoManager?.undo()
            XCTAssertEqual(editor.string, "/TestLaunch", "新草稿不得撤销回上一份正文")
            let richPasteboard = NSPasteboard.withUniqueName()
            defer { richPasteboard.releaseGlobally() }
            richPasteboard.declareTypes([.rtf], owner: nil)
            let pasted = NSAttributedString(string: "粘贴", attributes: [.font: NSFont.boldSystemFont(ofSize: 24)])
            richPasteboard.setData(pasted.rtf(from: NSRange(location: 0, length: pasted.length), documentAttributes: [:])!, forType: .rtf)
            editor.selectAll(nil)
            XCTAssertTrue(editor.insertPlainText(from: richPasteboard))
            XCTAssertEqual(editor.string, "粘贴")
            editor.undoManager?.undo()
            XCTAssertEqual(editor.string, "/TestLaunch")
            XCTAssertEqual(controller.session.draft.content, "/TestLaunch")

            editor.keyDown(with: returnEvent())
            XCTAssertTrue(attempts.isEmpty, "前导斜杠必须走普通 action，不能打开同名应用")
            XCTAssertEqual(editor.string, "")
            try await until { await notes.count == 1 }
            let firstNoteHTML = await notes.firstHTML()
            XCTAssertTrue(firstNoteHTML?.contains("/TestLaunch") == true)
            try await until { controller.session.activeSubmissionCount == 0 }
            XCTAssertTrue(controller.prepareRecordPanel() === panel)
            editor.insertText("TestLaunch", replacementRange: editor.selectedRange())
            XCTAssertEqual(controller.session.state.displayedActionTitle, "Open “TestLaunch”")

            let origin = panel.frame.origin
            var oldAnimationCompletions = 0
            panel.prepareSubmissionAnimation()
            XCTAssertNotNil(panel.submissionAnimationWindow)
            panel.animateOut(reduceMotion: true) { oldAnimationCompletions += 1 }
            panel.edgeGlow.start(reduceMotion: false)
            inspectBeforeOpen = {
                XCTAssertFalse(panel.isVisible)
                XCTAssertNil(panel.submissionAnimationWindow)
                XCTAssertFalse(panel.edgeGlow.isActive)
                XCTAssertEqual(panel.alphaValue, 1)
                XCTAssertEqual(panel.frame.origin, origin)
                XCTAssertEqual(editor.string, "TestLaunch")
                XCTAssertEqual(controller.session.draft.content, "TestLaunch")
            }
            editor.keyDown(with: returnEvent(repeatKey: true))
            XCTAssertTrue(attempts.isEmpty)
            editor.keyDown(with: returnEvent())
            XCTAssertEqual(attempts, [local.application.url])
            XCTAssertTrue(controller.session.state.isOpeningApplication)
            XCTAssertTrue(state.applicationUsage.isEmpty)
            XCTAssertEqual(editor.string, "TestLaunch")
            editor.keyDown(with: returnEvent())
            XCTAssertEqual(attempts.count, 1)
            let reply = try XCTUnwrap(completion)
            reply(.success(.current))
            XCTAssertFalse(controller.session.state.isOpeningApplication)
            XCTAssertEqual(editor.string, "")
            XCTAssertEqual(controller.session.draft.content, "")
            XCTAssertEqual(state.applicationUsage[attempts[0].path]?.openCount, 1)
            reply(.success(.current))
            XCTAssertEqual(state.applicationUsage[attempts[0].path]?.openCount, 1)
            inspectBeforeOpen = nil
            XCTAssertTrue(controller.prepareRecordPanel() === panel)
            try await Task.sleep(for: .milliseconds(200))
            XCTAssertEqual(oldAnimationCompletions, 0)
            XCTAssertTrue(editor.string.isEmpty)
            editor.insertText("、TestLaunch", replacementRange: editor.selectedRange())
            XCTAssertEqual(controller.session.draft.content, "、TestLaunch")
            XCTAssertEqual(controller.session.state.displayedActionTitle, "Save to Notes")
            editor.keyDown(with: returnEvent(code: 0x4C, modifiers: .shift))
            XCTAssertEqual(editor.string, "、TestLaunch\n")
            XCTAssertEqual(attempts.count, 1)
        }
    }
}

private actor MainPathNotesProbe {
    private(set) var requests: [AppleNotes.Request] = []
    var count: Int { requests.count }

    func firstHTML() -> String? {
        requests.first?.html
    }

    func record(_ request: AppleNotes.Request) -> AppleNotes.Response {
        requests.append(request)
        return .init(version: 1, requestID: request.requestID, status: "ok",
                     noteID: "note-\(requests.count)", folderID: request.folderID)
    }
}
