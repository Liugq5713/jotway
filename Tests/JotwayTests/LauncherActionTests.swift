import XCTest
@testable import Jotway

/// 启动器地板（Phase 1）：文本 → AI 处理（pass-through）→ 写入 Apple Notes。
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
        let action = AppleNotesAction(destination: destination) { request in
            captured = request
            return .init(version: 1, requestID: request.requestID, status: "ok",
                         noteID: "note-1", folderID: request.folderID,
                         plaintext: nil)
        }
        let prepared = try await action.prepare(ActionInput(
            identity: .init(draftID: UUID(), revision: 0), text: "明天要买牛奶"))
        let outcome = try await prepared.execute()
        XCTAssertEqual(outcome.localizedMessage, "Saved to Notes")
        XCTAssertEqual(captured?.operation, "create")
        XCTAssertEqual(captured?.folderID, destination.id)
        // 首行进入标题，正文用 pre 保留。
        XCTAssertTrue(captured?.html?.contains("明天要买牛奶") == true)
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
            userRules: [], explicitTargetID: nil, recognizedTargetID: nil, recognitionIsCurrent: false,
            defaultActionID: registry.fallbackActionID, applicationIDs: []))
        XCTAssertEqual(decision, .action("apple-notes", source: .localKeyword))
        registry.setEnabled(false, id: "apple-notes")
        XCTAssertEqual(registry.executionSnapshots().map(\.id), ["apple-notes"], "始终启用的 action 不接受公共开关")
        let unavailable = ProbeModule(action: AppleNotesAction(destination: nil),
                                      availability: .needsConfiguration(message: "请选择保存位置"))
        XCTAssertTrue(ActionRegistry(modules: [unavailable]).executionSnapshots().isEmpty)
    }

    func testRouteResolverUsesSingleDocumentedPriorityOrder() {
        let actions = [descriptor("explicit"), descriptor("rule"), descriptor("keyword", keyword: "route"),
                       descriptor("recognized"), descriptor("default")]
        let resolver = RouteResolver()
        func resolve(text: String = "route this", explicit: String? = nil,
                     rules: [IntentRule] = [], recognized: String? = "recognized",
                     current: Bool = true) -> RouteDecision {
            resolver.resolve(RouteInput(draft: RecordDraft(content: text), actions: actions,
                userRules: rules, explicitTargetID: explicit, recognizedTargetID: recognized,
                recognitionIsCurrent: current, defaultActionID: "default", applicationIDs: []))
        }

        XCTAssertEqual(resolve(explicit: "explicit", rules: [.init(phrase: "route", actionID: "rule")]),
                       .action("explicit", source: .explicit))
        XCTAssertEqual(resolve(rules: [.init(phrase: "route", actionID: "rule")]), .action("rule", source: .userRule))
        XCTAssertEqual(resolve(), .action("keyword", source: .localKeyword))
        XCTAssertEqual(resolve(text: "ordinary"), .action("recognized", source: .recognition))
        XCTAssertEqual(resolve(text: "ordinary", current: false), .action("default", source: .fallback))
        XCTAssertEqual(resolve(text: "ordinary", explicit: "missing"),
                       .unavailable(.targetUnavailable("missing"), source: .explicit))
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
