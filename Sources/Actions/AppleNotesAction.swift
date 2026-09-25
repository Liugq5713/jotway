import Foundation
import Observation
import SwiftUI

@MainActor @Observable
final class AppleNotesModule: ActionModule {
    nonisolated static let moduleDescriptor = ActionDescriptor(
        id: "apple-notes", title: "Save to Notes", settingsName: "Apple Notes",
        summary: "Save notes and ideas; the fallback when no clearer intent is found.",
        titleKey: "action.notes.title", settingsNameKey: "action.notes.settings_name",
        summaryKey: "action.notes.summary", systemImageName: "note.text", tint: .orange,
        settingsGroup: .init(id: "storage", title: "Save", order: 0, titleKey: "actions.group.storage"),
        enablementPolicy: .alwaysEnabled, fallbackPriority: 0,
        intentHints: IntentHints(localKeywords: ["记一下", "存备忘录", "留个备忘", "记个备忘", "存备忘", "先存",
                                                       "save to notes", "take a note"],
            modelBinding: .capture(criteria: """
                用户想把内容留下来、记一下、稍后处理，存进系统备忘录，而不是发给他人、搜索或打开应用。
                例：记一下 明天要买牛奶；存备忘录：这段代码；留个备忘 周五交周报；先存着待会儿看。
                纯粹的报告、引用他人的话、疑问句或明确要发给某人 / 搜索 / 打开某 App 的请求不属于此 action。
                """)),
        presentationPolicy: .returnToPreviousApplication)

    let descriptor = AppleNotesModule.moduleDescriptor
    @ObservationIgnored var onChange: (@MainActor () -> Void)?
    private let preferences: UserDefaults
    private let run: @MainActor @Sendable (AppleNotes.Request) async throws -> AppleNotes.Response
    private(set) var destination: AppleNotes.Destination?
    private(set) var repairFailure: ActionFailure?
    private(set) var configurationRevision = 0

    init(preferences: UserDefaults,
         run: @escaping @MainActor @Sendable (AppleNotes.Request) async throws -> AppleNotes.Response = {
             try await AppleNotes.run($0)
         }) {
        self.preferences = preferences
        self.run = run
        destination = preferences.data(forKey: "notesDestination")
            .flatMap { try? JSONDecoder().decode(AppleNotes.Destination.self, from: $0) }
    }

    var state: ActionModuleState {
        .init(configurationRevision: configurationRevision,
              availability: repairFailure.map { .needsConfiguration(message: $0.localizedDescription) }
                  ?? (destination == nil
                      ? .needsConfiguration(message: L10n.text("action.state.select_notes")) : .ready),
              summary: destination.map { L10n.text("action.state.save_to", $0.name) }
                  ?? L10n.text("action.state.no_destination"),
              hasSavedConfiguration: ["notesDestination", "notesTag", "notesAITagsEnabled",
                                      "aiRewriteEnabled.\(descriptor.id)", "aiRewritePrompt.\(descriptor.id)"]
                  .contains { preferences.object(forKey: $0) != nil })
    }

    var settings: ActionSettings? {
        ActionSettings { [unowned self] in AnyView(AppleNotesSettingsView(module: self)) }
    }

    var setup: ActionSetup? {
        let lifetime = AppleNotesSetupLifetime()
        return ActionSetup(title: L10n.text("action.notes.setup.action_title"),
                           invalidate: { lifetime.invalidate() }) { [self] onFinish in
            AnyView(AppleNotesSetupView(module: self, lifetime: lifetime, onFinish: onFinish))
        }
    }

    func refreshAvailability() {}

    func makeAction() -> any LauncherAction {
        let rewrites = isAIRewriteEnabled
        return AppleNotesAction(descriptor: descriptor, destination: destination,
            processor: actionTextProcessor(preferences: preferences, id: descriptor.id, mode: .notes,
                notesAutoTags: rewrites && isAITagsEnabled),
            tag: notesTag.isEmpty ? nil : notesTag, run: { [self] request in
                try await perform(request)
            })
    }

    var isAIRewriteEnabled: Bool { enabledPreference("aiRewriteEnabled.\(descriptor.id)") }
    var rewritePrompt: String { preferences.string(forKey: "aiRewritePrompt.\(descriptor.id)") ?? "" }
    var notesTag: String { preferences.string(forKey: "notesTag") ?? "Jotway" }
    var isAITagsEnabled: Bool { enabledPreference("notesAITagsEnabled") }

    func setDestination(_ value: AppleNotes.Destination) throws {
        let data = try JSONEncoder().encode(value)
        preferences.set(data, forKey: "notesDestination")
        guard preferences.data(forKey: "notesDestination") == data else {
            throw ActionFailure(localized: "error.destination_save_failed", code: .storage)
        }
        destination = value
        repairFailure = nil
        changed()
    }

    func loadDestinations() async throws -> [AppleNotes.Destination] {
        let expectedRevision = configurationRevision
        let response = try await perform(.init(requestID: UUID().uuidString, operation: "folders"))
        guard configurationRevision == expectedRevision else {
            throw ActionFailure(localized: "error.notes.configuration_changed", code: .stale)
        }
        guard let folders = response.folders else {
            throw ActionFailure(localized: "error.notes.folders_failed", code: .validation)
        }
        if repairFailure?.osStatus == -1743
            || (repairFailure != nil && folders.contains(where: { $0.id == destination?.id })) {
            repairFailure = nil
            changed()
        }
        guard !folders.isEmpty else {
            throw ActionFailure(localized: "error.notes.no_folders", code: .configuration,
                                osStatus: response.osStatus)
        }
        return folders
    }

    func verifyAndSetDestination(_ value: AppleNotes.Destination) async throws {
        let expectedRevision = configurationRevision
        let content = AppleNotes.content(fromPlainText: "Jotway Connection Test\nText, links, and escaping <&> test\nhttps://example.com\nThis item can be deleted after verification.")
        let requestID = UUID().uuidString
        let response = try await perform(.init(requestID: requestID, operation: "create",
                                           folderID: value.id, html: content.html))
        guard response.confirms(requestID: requestID, folderID: value.id, plaintext: content.plaintext) else {
            throw ActionFailure(localized: "error.notes.verification_failed",
                                code: .validation, osStatus: response.osStatus)
        }
        guard configurationRevision == expectedRevision else {
            throw ActionFailure(localized: "error.notes.configuration_changed", code: .stale)
        }
        try setDestination(value)
    }

    private func perform(_ request: AppleNotes.Request) async throws -> AppleNotes.Response {
        try Task.checkCancellation()
        let expectedRevision = configurationRevision
        do {
            let response = try await run(request)
            // A closed setup view cannot apply a late folder/verification response.
            try Task.checkCancellation()
            if let failure = AppleNotes.actionFailure(for: response, operation: request.operation) {
                throw failure
            }
            return response
        } catch {
            try Task.checkCancellation()
            if error is CancellationError { throw error }
            let failure = AppleNotes.actionFailure(for: error, operation: request.operation)
            let missingCurrentDestination = failure.osStatus == -1728
                && request.folderID != nil && request.folderID == destination?.id
            if configurationRevision == expectedRevision,
               failure.osStatus == -1743 || missingCurrentDestination {
                repairFailure = failure
                changed()
            }
            throw failure
        }
    }

    func setAIRewriteEnabled(_ enabled: Bool) { preferences.set(enabled, forKey: "aiRewriteEnabled.\(descriptor.id)"); changed() }
    func setRewritePrompt(_ text: String) {
        let key = "aiRewritePrompt.\(descriptor.id)"
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? preferences.removeObject(forKey: key) : preferences.set(text, forKey: key)
        changed()
    }
    func setNotesTag(_ raw: String) { preferences.set(cleanActionTag(raw), forKey: "notesTag"); changed() }
    func setAITagsEnabled(_ enabled: Bool) { preferences.set(enabled, forKey: "notesAITagsEnabled"); changed() }

    private func enabledPreference(_ key: String) -> Bool {
        preferences.object(forKey: key) == nil || preferences.bool(forKey: key)
    }
    private func changed() { configurationRevision &+= 1; onChange?() }
}

/// 存到备忘录（见 launcher-refactor.md §2.4-2.5）。
///
/// 双身份：既是可自然语言点名的普通 action（「记一下 XXX」「存备忘录：XXX」），
/// 又是识别不到意图时优先采用的已配置存入目标；未配置时由模块提供配置入口。
///
/// 写入用备忘录公开的 Apple Event 接口（复用 `AppleNotes.run`），系统自带、无需额外权限基础设施。
/// 形状：`原始文本 → AI 处理（第一版直通）→ 写入 Apple Notes → 结束`。过境即走，本地不留记录。
struct AppleNotesAction: LauncherAction {
    let descriptor: ActionDescriptor

    /// 保存位置（账号 / 文件夹）。为空时不可用，提示用户先在设置中选择。
    let destination: AppleNotes.Destination?
    /// AI 处理环节；第一版 pass-through。
    let processor: ActionTextProcessor
    /// 固定标签（已清洗、不含 # 前缀与空白）。非空时写入前追加到正文尾部，正文已含则跳过。
    let tag: String?
    /// 注入点：默认走真实 Apple Event，测试时替换。
    let run: @MainActor @Sendable (AppleNotes.Request) async throws -> AppleNotes.Response

    init(descriptor: ActionDescriptor = AppleNotesModule.moduleDescriptor,
         destination: AppleNotes.Destination?,
         processor: ActionTextProcessor = PassthroughTextProcessor(),
         tag: String? = nil,
         run: @escaping @MainActor @Sendable (AppleNotes.Request) async throws -> AppleNotes.Response
             = { try await AppleNotes.run($0) }) {
        self.descriptor = descriptor
        self.destination = destination
        self.processor = processor
        self.tag = tag
        self.run = run
    }

    func prepare(_ input: ActionInput) async throws -> PreparedAction {
        guard let destination else {
            throw ActionFailure(localized: "error.notes.choose_destination", code: .configuration)
        }
        let processed = try await processor.process(input.text).text
        let trimmed = processed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ActionFailure(localized: "error.notes.empty", code: .validation)
        }
        // 固定标签在转 HTML 前追加；正文已含该标签则跳过，避免与 AI 自动标签或用户手写重复。
        let body = Self.appendingTag(tag, to: processed)
        let content = AppleNotes.content(fromPlainText: body)
        let request = AppleNotes.Request(requestID: UUID().uuidString, operation: "create",
            folderID: destination.id, noteID: nil, html: content.html)
        return PreparedAction(actionID: descriptor.id, inputIdentity: input.identity) {
                do {
                    let response = try await run(request)
                    if let failure = AppleNotes.actionFailure(for: response, operation: request.operation) {
                        throw failure
                    }
                    guard response.noteID?.isEmpty == false else {
                        throw ActionFailure(localized: "error.notes.save_failed",
                                            code: .processFailed, osStatus: response.osStatus)
                    }
                    return ActionOutcome(messageKey: "result.notes.saved")
                } catch {
                    if error is CancellationError { throw error }
                    throw AppleNotes.actionFailure(for: error, operation: request.operation)
                }
            }
    }

    /// 在正文尾部追加固定标签（独占一行）。标签为空或正文已含该标签时原样返回。
    static func appendingTag(_ tag: String?, to text: String) -> String {
        guard let tag, !tag.isEmpty else { return text }
        let token = "#" + tag
        // 按空白切分逐个比对：AI 自动标签与用户手写标签都以空白分隔，命中即视为已存在。
        let existing = text.split(whereSeparator: { $0.isWhitespace }).contains { $0 == Substring(token) }
        if existing { return text }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? token : text + "\n\n" + token
    }

}
