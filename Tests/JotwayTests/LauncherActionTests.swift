import AppKit
import XCTest
@testable import Jotway

/// Notes 原文保护与启动器准备结果复用。
@MainActor
final class LauncherActionTests: XCTestCase {
    private let destination = AppleNotes.Destination(id: "folder-jotway", name: "测试 / Jotway")

    private actor PrepareProbe {
        private(set) var prepareCount = 0
        private(set) var executeCount = 0

        func prepared(_ input: ActionInput, actionID: String) -> PreparedAction {
            prepareCount += 1
            return PreparedAction(actionID: actionID, inputIdentity: input.identity) { [self] in
                await executed()
                return ActionOutcome(message: "done")
            }
        }

        private func executed() { executeCount += 1 }
    }

    private struct ProbeAction: LauncherAction {
        let descriptor: ActionDescriptor
        let probe: PrepareProbe

        func prepare(_ input: ActionInput) async throws -> PreparedAction {
            await probe.prepared(input, actionID: descriptor.id)
        }
    }

    private final class ProbeModule: ActionModule {
        let descriptor: ActionDescriptor
        var state: ActionModuleState
        var settings: ActionSettings? { nil }
        var onChange: (@MainActor () -> Void)?
        let action: any LauncherAction

        init(action: any LauncherAction, revision: Int = 0,
             availability: ActionAvailability = .ready) {
            self.action = action
            descriptor = action.descriptor
            state = .init(configurationRevision: revision, availability: availability,
                          summary: descriptor.summary, hasSavedConfiguration: false)
        }

        func refreshAvailability() {}
        func makeAction() -> any LauncherAction { action }
    }

    private func descriptor(_ id: String, keyword: String? = nil,
                            fallbackPriority: Int? = 0,
                            enablement: ActionEnablementPolicy = .alwaysEnabled) -> ActionDescriptor {
        ActionDescriptor(id: id, title: id, settingsName: id, summary: id, systemImageName: "circle",
            tint: .blue, settingsGroup: .init(id: "test", title: "Test", order: 0),
            enablementPolicy: enablement, fallbackPriority: fallbackPriority,
            intentHints: IntentHints(localKeywords: keyword.map { [$0] } ?? []),
            presentationPolicy: .returnToPreviousApplication)
    }

    func testAppleNotesActionCreatesNoteFromPlainText() async throws {
        var captured: AppleNotes.Request?
        var createCount = 0
        let action = AppleNotesAction(destination: destination) { request in
            captured = request
            createCount += 1
            return .init(version: 1, requestID: request.requestID, status: "ok",
                         noteID: "note-1", folderID: request.folderID,
                         plaintext: nil)
        }
        let prepared = try await action.prepare(ActionInput(
            identity: .init(draftID: UUID(), revision: 0), text: "明天要买牛奶"))
        let outcome = try await prepared.execute()
        XCTAssertEqual(outcome.localizedMessage, "Saved to Notes")
        XCTAssertEqual(createCount, 1)
        XCTAssertEqual(captured?.operation, "create")
        XCTAssertEqual(captured?.folderID, destination.id)
        let html = try XCTUnwrap(captured?.html)
        XCTAssertEqual(try renderedNotesText(html), NotesInitialTitleGenerator.placeholder(for: "明天要买牛奶") + "\n\n明天要买牛奶\n")
        XCTAssertEqual(try renderedNotesText(html).components(separatedBy: "明天要买牛奶").count - 1, 1)
    }

    func testAppleNotesContentPreservesOriginalWithoutDuplicatingFirstLine() throws {
        let fixtures: [(input: String, expected: String)] = [
            ("甲", "甲"),
            ("@notes 原文", "@notes 原文"), ("@codex 原文", "@codex 原文"),
            ("@personal 原文", "@personal 原文"), ("@clipboard 原文", "@clipboard 原文"),
            ("@calendar 明天开会", "@calendar 明天开会"),
            ("@reminders 买牛奶", "@reminders 买牛奶"),
            ("@reminder 买牛奶", "@reminder 买牛奶"),
            ("@chrome Swift", "@chrome Swift"),
            ("第一行\n第二行", "第一行\n第二行"),
            ("重复\n重复", "重复\n重复"),
            ("\n\n  第一行  \n\t第二行\n\n", "\n\n  第一行  \n\t第二行\n\n"),
            ("<alpha>&beta", "<alpha>&beta"),
            ("# 标题\n```swift\nlet value = 1\n```", "# 标题\n```swift\nlet value = 1\n```"),
            ("第一行\r\n第二行\r第三行", "第一行\n第二行\n第三行"),
        ]
        for fixture in fixtures {
            let content = AppleNotes.content(fromPlainText: fixture.input)
            XCTAssertEqual(content.plaintext, fixture.expected + "\n", fixture.input.debugDescription)
            // Native HTML import adds a final newline only when the original has none.
            let rendered = fixture.expected.hasSuffix("\n") ? fixture.expected : fixture.expected + "\n"
            XCTAssertEqual(try renderedNotesText(content.html), rendered,
                           fixture.input.debugDescription)
        }
    }

    func testAppleNotesContentAppendsSupplementAndTagsWithoutDuplicatingOriginal() throws {
        let original = "第一行\n第二行 #已有 #已有"
        let supplement = NotesSupplement(items: [.init(text: "需要确认哪些细节？")],
                                         tags: ["新增", "已有"])
        let content = AppleNotes.content(fromPlainText: original, supplement: supplement,
                                         tags: ["已有", "固定", "固定"])
        XCTAssertEqual(content.plaintext,
                       original + "\n\n────────────────────────────\n\nAI 洞察\n\n需要确认哪些细节？\n")
        let rendered = try renderedNotesText(content.html)
        XCTAssertTrue(rendered.hasPrefix(original + "\n"))
        XCTAssertEqual(rendered.components(separatedBy: "第一行").count - 1, 1)
        XCTAssertEqual(rendered.components(separatedBy: "第二行").count - 1, 1)
        XCTAssertEqual(rendered.components(separatedBy: "#已有").count - 1, 2)
        XCTAssertEqual(rendered.components(separatedBy: "需要确认哪些细节？").count - 1, 1)
        XCTAssertFalse(rendered.contains("#固定"))
        XCTAssertFalse(rendered.contains("#新增"))
    }

    private func renderedNotesText(_ html: String) throws -> String {
        try NSAttributedString(data: Data(html.utf8), options: [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ], documentAttributes: nil).string
    }

    func testAppleNotesActionUnavailableWithoutDestination() async {
        let action = AppleNotesAction(destination: nil)
        do {
            let prepared = try await action.prepare(ActionInput(
                identity: .init(draftID: UUID(), revision: 0), text: "记一下"))
            _ = try await prepared.execute()
            XCTFail("缺少保存位置时应抛错")
        } catch {
            XCTAssertTrue(error is ActionFailure)
        }
    }

    func testAppleNotesActionRejectsEmptyText() async {
        let action = AppleNotesAction(destination: destination) { _ in
            XCTFail("空文本不应发起写入")
            return .init(version: 1, requestID: "x", status: "ok")
        }
        do {
            _ = try await action.prepare(ActionInput(
                identity: .init(draftID: UUID(), revision: 0), text: "   \n  "))
            XCTFail("空文本应抛错")
        } catch {
            XCTAssertTrue(error is ActionFailure)
        }
    }

    func testRegistryEnableAndDefault() {
        let notes = AppleNotesAction(destination: destination)
        let registry = ActionRegistry(modules: [ProbeModule(action: notes)])
        XCTAssertEqual(registry.executionSnapshots().map(\.id), ["apple-notes"])
        let decision = RouteResolver().resolve(RouteInput(
            draft: RecordDraft(content: "记一下"), actions: registry.executionSnapshots().map(\.descriptor),
            explicitTargetID: nil, recognizedTargetID: nil, recognitionIsCurrent: false,
            defaultActionID: registry.fallbackActionID, applicationIDs: []))
        XCTAssertEqual(decision, .action("apple-notes", source: .localKeyword))
        for text in ["提醒我明天买牛奶", "Google 搜 Swift", "@calendar 明天开会",
                     "@reminders 买牛奶", "@reminder 买牛奶", "@chrome Swift", "今天可以聊聊吗？",
                     "@notes 原文", "@personal 原文", "@codex 原文", "@clipboard 原文"] {
            let decision = RouteResolver().resolve(RouteInput(draft: RecordDraft(content: text),
                actions: registry.executionSnapshots().map(\.descriptor), explicitTargetID: nil,
                recognizedTargetID: nil, recognitionIsCurrent: false,
                defaultActionID: registry.fallbackActionID, applicationIDs: []))
            XCTAssertEqual(decision, .action("apple-notes", source: .fallback))
            let input = ActionInput(identity: .init(draftID: UUID(), revision: 0), text: text)
            XCTAssertEqual(input.originalText, text)
        }
        registry.setEnabled(false, id: "apple-notes")
        XCTAssertEqual(registry.executionSnapshots().map(\.id), ["apple-notes"], "始终启用的 action 不接受公共开关")
        let unavailable = ProbeModule(action: AppleNotesAction(destination: nil),
                                      availability: .needsConfiguration(message: "请选择保存位置"))
        XCTAssertTrue(ActionRegistry(modules: [unavailable]).executionSnapshots().isEmpty)
    }

    func testRouteResolverUsesSingleDocumentedPriorityOrder() async throws {
        let actions = [descriptor("explicit"), descriptor("keyword", keyword: "route"),
                       descriptor("recognized"), descriptor("default"), descriptor("codex", keyword: "@codex")]
        let resolver = RouteResolver()
        func resolve(text: String = "route this", explicit: String? = nil,
                     recognized: String? = "recognized",
                     current: Bool = true) -> RouteDecision {
            resolver.resolve(RouteInput(draft: RecordDraft(content: text), actions: actions,
                explicitTargetID: explicit, recognizedTargetID: recognized,
                recognitionIsCurrent: current, defaultActionID: "default", applicationIDs: []))
        }

        XCTAssertEqual(resolve(explicit: "explicit"),
                       .action("explicit", source: .explicit))
        XCTAssertEqual(resolve(), .action("keyword", source: .localKeyword))
        XCTAssertEqual(resolve(text: "@codex task", current: false), .action("default", source: .fallback))
        XCTAssertEqual(resolve(text: "@codex task", explicit: "explicit"), .action("explicit", source: .explicit))
        XCTAssertEqual(resolve(text: "ordinary"), .action("recognized", source: .recognition))
        XCTAssertEqual(resolve(text: "ordinary", current: false), .action("default", source: .fallback))
        XCTAssertEqual(resolve(text: "ordinary", explicit: "missing"),
                       .unavailable(.targetUnavailable("missing"), source: .explicit))

        // Exercise target/template coordination without real actions, windows or clipboard data.
        let suite = "Jotway.TemplateTargets." + UUID().uuidString
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let pasteboard = NSPasteboard.withUniqueName()
        defer {
            preferences.removePersistentDomain(forName: suite)
            pasteboard.releaseGlobally()
            try? FileManager.default.removeItem(at: directory)
        }
        let history = ClipboardHistory(preferences: preferences,
            store: ClipboardHistoryStore(url: directory.appendingPathComponent("history.sqlite")),
            idleSeconds: { 0 }, recognize: { _ in XCTFail("Template selection must not recognize images"); return "" })
        let clipboard = ClipboardService(pasteboard: pasteboard,
            sourceSettings: BrowserSourceSettings(preferences: preferences), history: history,
            preferences: preferences, foreground: { .init(bundle: nil, pid: 0) },
            readSource: { _ in XCTFail("Template selection must not read a browser"); return nil })
        let probe = PrepareProbe()
        let registry = ActionRegistry(modules: [descriptor("apple-notes"),
            CodexModule.moduleDescriptor,
            ClipboardModule.moduleDescriptor].map { ProbeModule(action: ProbeAction(descriptor: $0, probe: probe)) })
        let session = LauncherSession(registry: registry,
            recorder: OperationRecorder(repository: .inMemory(), enabled: false),
            catalog: ApplicationCatalog(applications: []), clipboard: clipboard,
            applicationUsage: { [:] }, recordApplicationOpen: { _ in XCTFail("No app opening"); return false })
        var insertions = 0
        var acceptInsertion = true
        var endedFilling = 0
        session.handleEffect = { effect in
            switch effect {
            case .insertTemplate(_, let identity):
                XCTAssertEqual(identity.draftID, session.draft.id)
                XCTAssertEqual(identity.revision, session.draftRevision)
                insertions += 1
                return acceptInsertion
            case .endTemplateEditing: endedFilling += 1
            case .prepareSubmission, .showActionSetup, .openApplication:
                XCTFail("Choosing a target or template must not execute or configure")
            default: break
            }
            return true
        }
        XCTAssertTrue(session.prepare())
        XCTAssertEqual(Set(session.state.intentCandidates.map(\.id)), Set(["codex", "apple-notes"]))
        session.send(.inputChanged("draft"))
        session.send(.selectTarget("clipboard"))
        XCTAssertFalse(session.state.hasExplicitTarget)
        let originalCopyVersion = pasteboard.changeCount
        for targetID in ["apple-notes", "codex"] {
            session.send(.inputChanged(targetID == "codex" ? "" : "draft"))
            session.send(.selectTarget(targetID))
            if targetID == "codex" {
                XCTAssertTrue(session.state.showsCodexRecentTasks, "The explicit target exposes recent tasks without a prefix")
            }
            session.send(.inputChanged("@记录"))
            let draftID = session.draft.id, revision = session.draftRevision
            let template = try XCTUnwrap(session.state.templateCandidates.first)
            XCTAssertFalse(session.state.showsCodexRecentTasks)
            XCTAssertFalse(session.state.canConfirm)
            acceptInsertion = false
            session.send(.selectTemplate(template))
            XCTAssertEqual(session.draft.content, "@记录", "Rejected native edits preserve the query")
            XCTAssertEqual(session.draftRevision, revision)
            acceptInsertion = true
            session.send(.selectTemplate(template))
            XCTAssertEqual(session.draft.content, try TemplateExpansion.parse(template.body).text)
            XCTAssertEqual(session.draft.id, draftID)
            XCTAssertEqual(session.draftRevision, revision + 1, "One accepted insertion commits exactly one draft update")
            XCTAssertTrue(session.state.hasExplicitTarget)
            XCTAssertEqual(session.state.intentCandidates.first(where: \.isSelected)?.id, targetID)
            XCTAssertNil(session.state.clipboardHistory)
            session.send(.inputChanged("@clipboard literal query"))
            XCTAssertFalse(session.state.isTemplateMenuVisible)
            XCTAssertEqual(session.draft.content, "@clipboard literal query")
            XCTAssertEqual(session.state.intentCandidates.first(where: \.isSelected)?.id, targetID)
        }
        XCTAssertEqual(insertions, 4)
        XCTAssertEqual(pasteboard.changeCount, originalCopyVersion, "Choosing templates never copies")
        session.send(.toggleMode)
        XCTAssertGreaterThan(endedFilling, 0)
        XCTAssertFalse(session.state.isTemplateMenuVisible)
        session.send(.panelDismissed)
        try await Task.sleep(for: .milliseconds(50))
        let executions = await probe.executeCount
        XCTAssertEqual(executions, 0)
    }

    func testActionExecutorReusesPreparedActionForExecution() async throws {
        let probe = PrepareProbe()
        let action = ProbeAction(descriptor: descriptor("probe"), probe: probe)
        let input = ActionInput(identity: .init(draftID: UUID(), revision: 7), text: "same input")
        let executor = ActionExecutor()
        let snapshot = ActionExecutionSnapshot(id: "probe", descriptor: action.descriptor,
            configurationIdentity: .init(moduleInstance: UUID(), revision: 1), action: action)

        executor.schedule(snapshot: snapshot, input: input, debounce: .zero)
        let outcome = try await executor.executionTask(snapshot: snapshot, input: input).value

        let counts = await (probe.prepareCount, probe.executeCount)
        XCTAssertEqual(outcome.message, "done")
        XCTAssertEqual(counts.0, 1)
        XCTAssertEqual(counts.1, 1)

        let changedConfiguration = ActionExecutionSnapshot(id: "probe", descriptor: action.descriptor,
            configurationIdentity: .init(moduleInstance: snapshot.configurationIdentity.moduleInstance,
                                         revision: 2), action: action)
        executor.schedule(snapshot: changedConfiguration, input: input, debounce: .zero)
        _ = try await executor.executionTask(snapshot: changedConfiguration, input: input).value
        let changedCounts = await (probe.prepareCount, probe.executeCount)
        XCTAssertEqual(changedCounts.0, 2, "正文未变但配置身份变化时不能复用旧准备结果")
        XCTAssertEqual(changedCounts.1, 2)
    }

}
