import AppKit
import Carbon
import NaturalLanguage

/// 通过备忘录公开的 Apple Event 接口保存与回读；正文始终作为数据传递。
enum AppleNotes {
    struct Destination: Codable, Equatable, Sendable, Identifiable {
        let id: String
        let name: String
    }

    struct Content: Equatable, Sendable {
        let html: String
        let plaintext: String
        var itemCount = 0
        var historyCount = 0
    }

    struct Request: Sendable {
        let requestID: String
        let operation: String
        var folderID: String?
        var noteID: String?
        var html: String?
        var historyRead = false
        var allowAuthorization = false
        var validateBeforeSend: (@Sendable () async throws -> Void)? = nil
        var metadataProgress: (@MainActor @Sendable (Int, Int) async -> Void)? = nil
        var folderProgress: (@MainActor @Sendable (Int) async -> Void)? = nil
        var updateGuard: NotesUpdateGuard? = nil
        var managedConfirmation = false
        var readDeadline: ContinuousClock.Instant? = nil
        var groupingDiagnostics: NotesGroupingDiagnostics? = nil
    }

    struct Response: Sendable {
        var version: Int
        var requestID: String?
        var status: String
        var folders: [Destination]?
        var noteID: String?
        var folderID: String?
        var plaintext: String?
        var message: String?
        /// 失败时的 Apple Event OSStatus（如 -1743 权限、-1728 目标不存在），用于诊断日志。
        var osStatus: Int?
        var sources: [NotesSource]?
        var sourceBody: NotesSourceBody?
    }

    struct Failure: LocalizedError {
        enum Kind: Sendable { case operation, launch }
        let message: String
        /// 仅能证明请求根本未送达的 Apple Event 错误可直接重试。
        var notStarted = false
        /// 失败时的 Apple Event OSStatus，用于诊断日志。
        var osStatus: Int? = nil
        var kind: Kind = .operation
        var errorDescription: String? { message }
    }

    /// Preserve actionable Apple Event errors at the injectable adapter boundary.
    /// External error text is not shown directly because it may contain note content.
    static func actionFailure(for response: Response, operation: String) -> ActionFailure? {
        guard response.status != "ok" else { return nil }
        return actionFailure(osStatus: response.osStatus, operation: operation,
                             mayHaveWritten: response.status == "uncertain")
    }

    static func actionFailure(for error: Error, operation: String) -> ActionFailure {
        if case NotesHistoryError.stale = error {
            return ActionFailure(localized: "error.notes.configuration_changed", code: .stale)
        }
        if let failure = error as? ActionFailure {
            guard let status = failure.osStatus, [-1743, -1728].contains(status) else { return failure }
            return actionFailure(osStatus: status, operation: operation,
                                 mayHaveWritten: failure.executionOutcome == .unknown)
        }
        if let failure = error as? Failure {
            if failure.kind == .launch {
                return ActionFailure(localized: "error.notes.launch_failed", code: .unavailable,
                                     osStatus: failure.osStatus)
            }
            return actionFailure(osStatus: failure.osStatus, operation: operation,
                                 mayHaveWritten: !failure.notStarted && ["create", "update"].contains(operation))
        }
        let error = error as NSError
        return actionFailure(osStatus: error.domain == NSOSStatusErrorDomain ? error.code : nil,
                             operation: operation)
    }

    private static func actionFailure(osStatus: Int?, operation: String,
                                      mayHaveWritten: Bool? = nil) -> ActionFailure {
        let uncertain = mayHaveWritten ?? ["create", "update"].contains(operation)
        let outcome: OperationExecutionOutcome = uncertain ? .unknown : .failed
        switch osStatus {
        case -1743, -1744:
            return ActionFailure(localized: "error.notes.automation_denied", code: .configuration,
                                 osStatus: osStatus, executionOutcome: outcome)
        case -1728:
            return ActionFailure(localized: "error.notes.destination_missing", code: .configuration,
                                 osStatus: osStatus, executionOutcome: outcome)
        default:
            let key = operation == "folders" ? "error.notes.folders_failed"
                : uncertain ? "error.notes.save_uncertain" : "error.notes.save_failed"
            return ActionFailure(localized: key, code: osStatus == -1712 ? .timeout : .processFailed,
                                 osStatus: osStatus,
                                 executionOutcome: outcome)
        }
    }

    /// Preserve the original once; Notes determines its title from the supplied body.
    /// A span inside pre prevents HTML's special handling of a newline immediately after <pre>.
    static func content(fromPlainText text: String, supplement: NotesSupplement = .empty,
                        tags: [String] = []) -> Content {
        let original = normalizedLines(text)
        func preservedBlock(_ value: String, region: String,
                            fontFamily: String = "-apple-system, Helvetica, sans-serif") -> String {
            let escaped = value.components(separatedBy: "\n").map { line in
                let url = line.trimmingCharacters(in: .whitespaces)
                guard region == "original", BrowserSource.validated(title: "", url: url) != nil,
                      let range = line.range(of: url) else { return escapedHTML(line) }
                let href = escapedHTML(url).replacingOccurrences(of: "\"", with: "&quot;")
                return escapedHTML(String(line[..<range.lowerBound])) + "<a href=\"\(href)\">\(escapedHTML(url))</a>"
                    + escapedHTML(String(line[range.upperBound...]))
            }.joined(separator: "\n")
            return "<pre data-jotway-region=\"\(region)\" style=\"font-family: \(fontFamily); font-size: 14px; white-space: pre-wrap; overflow-wrap: anywhere; margin: 0;\"><span>\(escaped)</span></pre>"
        }
        var html = preservedBlock(original, region: "original")
        var plaintext = original
        // Saved content follows the draft's language independently of the English app UI.
        let language = NLLanguageRecognizer.dominantLanguage(for: original)
        let isChinese = language == .simplifiedChinese || language == .traditionalChinese
        func label(_ english: String, _ chinese: String) -> String { isChinese ? chinese : english }
        func sourceLink(_ title: String, noteID: String) -> String {
            guard let url = NotesSourceLink.url(noteID: noteID) else { return escapedHTML(title) }
            let href = escapedHTML(url.absoluteString).replacingOccurrences(of: "\"", with: "&quot;")
            return "<a href=\"\(href)\">\(escapedHTML(title))</a>"
        }
        // Apply bounds at the final write boundary too, including non-model processors.
        var usedText = [original]
        var usedNotes = Set<String>()
        var usedEvidence = Set<String>()
        let history = Array(supplement.history.filter { item in
            guard AINotesSupplementProcessor.validAddition(item.text),
                  AINotesSupplementProcessor.hasEvidence(item.source.text),
                  NotesSourceLink.url(noteID: item.source.noteID) != nil,
                  !usedText.contains(where: { AINotesSupplementProcessor.overlaps(item.text, $0) }),
                  !AINotesSupplementProcessor.overlaps(item.source.text, original),
                  usedNotes.insert(item.source.noteID).inserted,
                  usedEvidence.insert(AINotesSupplementProcessor.comparisonText(item.source.text)).inserted else { return false }
            usedText.append(item.text)
            return true
        }.prefix(NotesSupplement.maximumHistoryCount))
        let items = Array(supplement.items.filter { item in
            guard AINotesSupplementProcessor.validAddition(item.text),
                  !usedText.contains(where: { AINotesSupplementProcessor.overlaps(item.text, $0) }),
                  !history.contains(where: { AINotesSupplementProcessor.overlaps(item.text, $0.source.text) }) else { return false }
            usedText.append(item.text)
            return true
        }.prefix(NotesSupplement.maximumItemCount))
        // Each row supplies the same visible text to HTML and the provenance tail.
        // Empty div rows provide spacing without paragraph margins or quote indentation.
        var rows: [(text: String, html: String)] = []
        func row(_ text: String = "", html: String? = nil) {
            rows.append((text, html ?? (text.isEmpty ? "<br>" : escapedHTML(text))))
        }
        func heading(_ text: String) {
            row()
            row(text, html: "<b>\(escapedHTML(text))</b>")
            row()
        }
        if !items.isEmpty || !history.isEmpty { row(NotesContentFormat.divider) }
        if !items.isEmpty {
            heading(label(NotesContentFormat.englishInsights, NotesContentFormat.chineseInsights))
            for (index, item) in items.enumerated() {
                if index > 0 { row() }
                row(item.text)
            }
        }
        if !history.isEmpty {
            heading(label(NotesContentFormat.englishRelated, NotesContentFormat.chineseRelated))
            for (index, item) in history.enumerated() {
                if index > 0 { row() }
                var title = item.source.title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                if title.hasPrefix("《"), title.hasSuffix("》") {
                    title = String(title.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                }
                let shortTitle = title.isEmpty ? label("Untitled note", "无标题笔记") : abbreviated(title, limit: 48)
                let prefix = label("Source: ", "来源：")
                let linkedTitle = isChinese ? "《\(shortTitle)》↗" : "\(shortTitle) ↗"
                row(item.text)
                row(prefix + linkedTitle, html: escapedHTML(prefix) + sourceLink(linkedTitle, noteID: item.source.noteID))
            }
        }
        if !rows.isEmpty {
            let trailingBreaks = original.reversed().prefix(while: { $0 == "\n" }).count
            plaintext += String(repeating: "\n", count: max(0, 2 - trailingBreaks))
                + rows.map(\.text).joined(separator: "\n")
            // The pre block supplies its own terminating newline when one is missing.
            let blankRows = max(0, 2 - max(1, trailingBreaks))
            html += "<div data-jotway-region=\"generated\" style=\"font-family: -apple-system, Helvetica, sans-serif; font-size: 14px;\">"
                + String(repeating: "<div><br></div>", count: blankRows)
                + rows.map { "<div>\($0.html)</div>" }.joined() + "</div>"
        }
        // Tag preferences and legacy processor fields remain stored but never append text.
        return Content(html: html, plaintext: plaintext + "\n", itemCount: items.count, historyCount: history.count)
    }

    private static func normalizedLines(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    private static func abbreviated(_ text: String, limit: Int) -> String {
        text.count > limit ? String(text.prefix(limit - 1)) + "…" : text
    }

    private static func escapedHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    @MainActor
    static func authorizationStatus() -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.Notes")
        return AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, false)
    }

    @MainActor
    static func run(_ request: Request) async throws -> Response {
        try Task.checkCancellation()
        if request.historyRead && !request.allowAuthorization {
            let status = authorizationStatus()
            guard status == noErr else {
                throw Failure(message: L10n.text("notes.history.error.permission"), osStatus: Int(status))
            }
        }
        if NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Notes").isEmpty {
            let options = NSWorkspace.OpenConfiguration()
            options.activates = false
            options.addsToRecentItems = false
            do {
                _ = try await NSWorkspace.shared.openApplication(
                    at: URL(fileURLWithPath: "/System/Applications/Notes.app"), configuration: options)
            } catch {
                throw Failure(message: L10n.text("notes.launch_failed", error.localizedDescription),
                              notStarted: true, kind: .launch)
            }
        }
        try Task.checkCancellation()
        try await request.validateBeforeSend?()
        // AESend 等待不占用主线程，关窗不会取消外部写入。超时后绝不自动重发。
        let operation = Task.detached(priority: request.historyRead ? .utility : .userInitiated) {
            let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.Notes")
            // 类和属性代码来自 Notes.sdef；不依赖脚本、快捷指令或用户界面。
            func object(_ kind: OSType, in container: NSAppleEventDescriptor = .null(),
                        form: OSType, key: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
                let specifier = NSAppleEventDescriptor.record()
                specifier.setDescriptor(.init(typeCode: kind), forKeyword: AEKeyword(keyAEDesiredClass))
                specifier.setDescriptor(container, forKeyword: AEKeyword(keyAEContainer))
                specifier.setDescriptor(.init(enumCode: form), forKeyword: AEKeyword(keyAEKeyForm))
                specifier.setDescriptor(key, forKeyword: AEKeyword(keyAEKeyData))
                guard let result = specifier.coerce(toDescriptorType: DescType(typeObjectSpecifier)) else {
                    throw Failure(message: L10n.text("notes.prepare_failed"))
                }
                return result
            }
            var readStage: NotesGroupingDiagnostics.Stage = ["create", "update"].contains(request.operation) ? .finalValidation : .preparation
            func send(_ command: AEEventID, _ parameters: [AEKeyword: NSAppleEventDescriptor], suite: AEEventClass = AEEventClass(kAECoreSuite), allowEmptyResult: Bool = false) throws -> NSAppleEventDescriptor {
                if request.historyRead { try Task.checkCancellation() }
                let event = NSAppleEventDescriptor(eventClass: suite, eventID: command,
                    targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
                for (key, value) in parameters { event.setParam(value, forKeyword: key) }
                var timeout: TimeInterval = request.historyRead ? 30 : 120
                if let deadline = request.readDeadline {
                    let remaining = ContinuousClock.now.duration(to: deadline)
                    guard remaining > .zero else { throw NSError(domain: NSOSStatusErrorDomain, code: -1712) }
                    timeout = min(timeout, Double(remaining.components.seconds) + Double(remaining.components.attoseconds) / 1e18)
                }
                let reply: NSAppleEventDescriptor
                if let metrics = request.groupingDiagnostics, [AEEventID(kAEGetData), AEEventID(kAECountElements)].contains(command) {
                    reply = try metrics.read(readStage) {
                        try event.sendEvent(options: request.historyRead && !request.allowAuthorization ? [.waitForReply, .neverInteract] : [.waitForReply, .canInteract], timeout: timeout)
                    }
                } else {
                    reply = try event.sendEvent(options: request.historyRead && !request.allowAuthorization ? [.waitForReply, .neverInteract] : [.waitForReply, .canInteract], timeout: timeout)
                }
                if let code = reply.paramDescriptor(forKeyword: AEKeyword(keyErrorNumber))?.int32Value, code != 0 {
                    let message = reply.paramDescriptor(forKeyword: AEKeyword(keyErrorString))?.stringValue
                        ?? L10n.text("notes.operation_failed")
                    throw NSError(domain: NSOSStatusErrorDomain, code: Int(code), userInfo: [NSLocalizedDescriptionKey: message])
                }
                guard let result = reply.paramDescriptor(forKeyword: AEKeyword(keyDirectObject)) else {
                    if allowEmptyResult { return .null() }
                    throw Failure(message: L10n.text("notes.no_verifiable_result"))
                }
                return result
            }
            func property(_ code: OSType, of container: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
                let reference = try object(OSType(cProperty), in: container, form: OSType(formPropertyID), key: .init(typeCode: code))
                return try send(AEEventID(kAEGetData), [AEKeyword(keyDirectObject): reference])
            }
            func text(_ code: OSType, of container: NSAppleEventDescriptor) throws -> String {
                guard let result = try property(code, of: container).stringValue else {
                    throw Failure(message: L10n.text("notes.incomplete_content"))
                }
                return result
            }
            func elements(_ kind: OSType, in container: NSAppleEventDescriptor = .null()) throws -> [NSAppleEventDescriptor] {
                guard let all = NSAppleEventDescriptor(descriptorType: DescType(typeAbsoluteOrdinal),
                    data: NSAppleEventDescriptor(enumCode: OSType(kAEAll)).data) else {
                    throw Failure(message: L10n.text("notes.prepare_list_failed"))
                }
                let reference = try object(kind, in: container, form: OSType(formAbsolutePosition), key: all)
                let list = try send(AEEventID(kAEGetData), [AEKeyword(keyDirectObject): reference])
                guard list.descriptorType == DescType(typeAEList) else {
                    throw Failure(message: L10n.text("notes.list_failed"))
                }
                return try (0..<list.numberOfItems).map {
                    guard let item = list.atIndex($0 + 1) else {
                        throw Failure(message: L10n.text("notes.list_incomplete"))
                    }
                    return item
                }
            }
            var mayHaveWritten = false
            do {
                if request.operation == "folders" {
                    // Defaults can be unavailable while accounts are syncing. They only
                    // determine ordering; permission errors must still reach the caller.
                    func optionalDefault(_ read: () throws -> NSAppleEventDescriptor) throws -> NSAppleEventDescriptor? {
                        do { return try read() }
                        catch {
                            let error = error as NSError
                            if error.domain == NSOSStatusErrorDomain, error.code == -1743 { throw error }
                            return nil
                        }
                    }
                    // History needs the selected folder set, not the default save destination.
                    let defaultAccount = try request.historyRead ? nil : optionalDefault { try property(0x64666163, of: .null()) } // dfac
                    let defaultAccountID = try defaultAccount.flatMap { account in
                        try optionalDefault { try property(0x49442020, of: account) }?.stringValue // ID
                    }
                    var folders: [Destination] = []
                    var preferredFolderIDs: [String] = []
                    for account in try elements(0x61636374) { // acct
                        let accountID = try request.historyRead ? nil : text(0x49442020, of: account) // ID
                        let accountName = try text(0x706E616D, of: account) // pnam
                        if !request.historyRead, let defaultFolder = try optionalDefault({ try property(0x64666F6C, of: account) }), // dfol
                           let folderID = try optionalDefault({ try property(0x49442020, of: defaultFolder) })?.stringValue {
                            if accountID == defaultAccountID { preferredFolderIDs.insert(folderID, at: 0) }
                            else { preferredFolderIDs.append(folderID) }
                        }
                        var visited = Set<String>()
                        func appendFolders(in container: NSAppleEventDescriptor, path: String) async throws {
                            for folder in try elements(0x63666F6C, in: container) {
                                let id = try text(0x49442020, of: folder)
                                guard visited.insert(id).inserted else { continue }
                                let name = try text(0x706E616D, of: folder)
                                // Notes normally omits trash from scripting collections. Also exclude
                                // exposed system trash names; never read its body as an index source.
                                if request.historyRead && ["Recently Deleted", "最近删除", "最近刪除"].contains(name) { continue }
                                let fullName = path + " / " + name
                                folders.append(Destination(id: id, name: fullName))
                                await request.folderProgress?(folders.count)
                                if request.historyRead { try await appendFolders(in: folder, path: fullName) }
                            }
                        }
                        try await appendFolders(in: account, path: accountName)
                    }
                    // Prefer the system default, then another account's default, before
                    // falling back to a folder exposed by Notes' scripting interface.
                    if let defaultFolder = preferredFolderIDs.lazy.compactMap({ id in
                        folders.first(where: { $0.id == id })
                    }).first, let index = folders.firstIndex(where: { $0.id == defaultFolder.id }) {
                        folders.insert(folders.remove(at: index), at: 0)
                    }
                    return Response(version: 1, requestID: request.requestID, status: "ok", folders: folders)
                }
                if request.operation == "historyMetadata", let folderID = request.folderID {
                    let folder = try object(0x63666F6C, form: OSType(formUniqueID), key: .init(string: folderID))
                    func count() throws -> Int {
                        let result = try send(AEEventID(kAECountElements), [AEKeyword(keyDirectObject): folder,
                            AEKeyword(keyAEObjectClass): .init(typeCode: 0x6E6F7465)])
                        guard let number = result.coerce(toDescriptorType: DescType(typeSInt32)) else {
                            throw AppleNotesMetadata.Failure.unsupportedResponse
                        }
                        let value = Int(number.int32Value)
                        guard value >= 0 else { throw NotesHistoryError.response }
                        return value
                    }
                    do {
                        let total = try count()
                        let sources = try await AppleNotesMetadata.read(folderID: folderID, count: total, property: { code, range in
                            // Range endpoints are relative to the range's container, not
                            // independent folder specifiers (typeCurrentContainer in AEObjects).
                            guard let currentContainer = NSAppleEventDescriptor(descriptorType: DescType(typeCurrentContainer), data: Data()) else {
                                throw AppleNotesMetadata.Failure.unsupportedResponse
                            }
                            let bounds = NSAppleEventDescriptor.record()
                            bounds.setDescriptor(try object(0x6E6F7465, in: currentContainer, form: OSType(formAbsolutePosition),
                                key: .init(int32: Int32(range.lowerBound))), forKeyword: AEKeyword(keyAERangeStart))
                            bounds.setDescriptor(try object(0x6E6F7465, in: currentContainer, form: OSType(formAbsolutePosition),
                                key: .init(int32: Int32(range.upperBound))), forKeyword: AEKeyword(keyAERangeStop))
                            guard let rangeDescriptor = bounds.coerce(toDescriptorType: DescType(typeRangeDescriptor)) else {
                                throw AppleNotesMetadata.Failure.unsupportedResponse
                            }
                            let notes = try object(0x6E6F7465, in: folder, form: OSType(formRange), key: rangeDescriptor)
                            return try property(code, of: notes)
                        }, progress: request.metadataProgress)
                        guard try count() == total else { throw NotesHistoryError.stale }
                        return Response(version: 1, requestID: request.requestID, status: "ok", sources: sources)
                    } catch {
                        try Task.checkCancellation()
                        let native = error as NSError
                        // Older Notes versions may not support collection properties. Keep the
                        // public per-note path, but never retry permission errors or timeouts.
                        guard error is AppleNotesMetadata.Failure
                            || (native.domain == NSOSStatusErrorDomain && [-1700, -1708, -1728].contains(native.code)) else { throw error }
                    }
                    let notes = try elements(0x6E6F7465, in: folder)
                    var sources: [NotesSource] = []
                    await request.metadataProgress?(0, notes.count)
                    for note in notes {
                        guard let created = try property(0x61736364, of: note).dateValue,
                              let modified = try property(0x61736D6F, of: note).dateValue else {
                            throw Failure(message: L10n.text("notes.incomplete_content"))
                        }
                        sources.append(try NotesSource(id: text(0x49442020, of: note), folderID: folderID,
                            title: text(0x706E616D, of: note), created: created, modified: modified,
                            locked: property(0x70777072, of: note).booleanValue,
                            shared: property(0x73687264, of: note).booleanValue))
                        await request.metadataProgress?(sources.count, notes.count)
                    }
                    return Response(version: 1, requestID: request.requestID, status: "ok", sources: sources)
                }
                if ["historyBody", "historyOpen"].contains(request.operation), let id = request.noteID {
                    let note = try object(0x6E6F7465, form: OSType(formUniqueID), key: .init(string: id))
                    guard try text(0x49442020, of: note) == id else { throw NotesHistoryError.response }
                    if request.operation == "historyOpen" {
                        _ = try send(0x73686F77, [AEKeyword(keyDirectObject): note], suite: 0x6E6F7465)
                        return Response(version: 1, requestID: request.requestID, status: "ok")
                    }
                    guard try !property(0x70777072, of: note).booleanValue else { throw NotesHistoryError.unavailable }
                    let body = try NotesSourceBody(text: text(0x74657874, of: note), html: text(0x626F6479, of: note),
                                                   attachments: elements(0x61747473, in: note).count)
                    return Response(version: 1, requestID: request.requestID, status: "ok", sourceBody: body)
                }
                // Specific IDs only. Notes.sdef does not establish arbitrary-ID batch semantics.
                func readState(_ note: NSAppleEventDescriptor) throws -> NotesSource {
                    let container = try property(0x636E7472, of: note)
                    guard let created = try property(0x61736364, of: note).dateValue,
                          let modified = try property(0x61736D6F, of: note).dateValue else {
                        throw NotesHistoryError.response
                    }
                    return try NotesSource(id: text(0x49442020, of: note), folderID: text(0x49442020, of: container),
                        title: "", created: created, modified: modified,
                        locked: property(0x70777072, of: note).booleanValue,
                        shared: property(0x73687264, of: note).booleanValue)
                }
                func readManaged(_ note: NSAppleEventDescriptor) throws -> (NotesSource, NotesSourceBody) {
                    let state = try readState(note)
                    guard !state.locked, !state.shared else { throw NotesHistoryError.stale }
                    let title = try text(0x706E616D, of: note)
                    let body = try NotesSourceBody(text: text(0x74657874, of: note), html: text(0x626F6479, of: note),
                                                   attachments: elements(0x61747473, in: note).count)
                    // Never stamp an earlier body with metadata obtained after that body changed.
                    guard try property(0x61736D6F, of: note).dateValue == state.modified else {
                        throw NotesHistoryError.response
                    }
                    return (.init(id: state.id, folderID: state.folderID, title: title, created: state.created,
                                  modified: state.modified, locked: state.locked, shared: state.shared), body)
                }
                if ["managedState", "managedRead", "update"].contains(request.operation), let id = request.noteID {
                    let note = try object(0x6E6F7465, form: OSType(formUniqueID), key: .init(string: id))
                    if request.operation == "managedState" {
                        let state = try readState(note)
                        guard state.id == id else { throw NotesHistoryError.response }
                        return Response(version: 1, requestID: request.requestID, status: "ok", sources: [state])
                    }
                    if request.operation == "update" {
                        guard let protection = request.updateGuard, protection.noteID == id,
                              protection.scope.folderID == request.folderID, let html = request.html else {
                            throw NotesHistoryError.stale
                        }
                        try Task.checkCancellation()
                        try await request.validateBeforeSend?()
                        // No suspension between the final read/guard and update. Notes does not
                        // offer cross-process compare-and-swap; external edits can still race.
                        readStage = .finalValidation
                        let (source, body) = try readManaged(note)
                        try protection.validate(source: source, body: body)
                        try Task.checkCancellation()
                        let reference = try object(OSType(cProperty), in: note,
                            form: OSType(formPropertyID), key: .init(typeCode: 0x626F6479))
                        mayHaveWritten = true
                        _ = try send(AEEventID(kAESetData), [AEKeyword(keyDirectObject): reference,
                            AEKeyword(keyAEData): .init(string: html)], allowEmptyResult: true)
                    }
                    if request.operation == "update" { readStage = .readback }
                    let (source, body) = try readManaged(note)
                    return Response(version: 1, requestID: request.requestID, status: "ok", noteID: source.id,
                        folderID: source.folderID, plaintext: body.text, sources: [source], sourceBody: body)
                }
                guard ["create", "verify"].contains(request.operation), let folderID = request.folderID else {
                    throw Failure(message: L10n.text("destination.invalid"))
                }
                let folder = try object(0x63666F6C, form: OSType(formUniqueID), key: .init(string: folderID))
                guard try text(0x49442020, of: folder) == folderID else {
                    throw Failure(message: L10n.text("destination.changed"))
                }
                var noteID = request.noteID
                if request.operation == "create" {
                    guard let html = request.html else { throw Failure(message: L10n.text("error.empty_content")) }
                    let properties = NSAppleEventDescriptor.record()
                    properties.setDescriptor(.init(string: html), forKeyword: 0x626F6479) // body
                    // Folder readback can outlive cancellation or a destination change.
                    try Task.checkCancellation()
                    try await request.validateBeforeSend?()
                    try Task.checkCancellation()
                    mayHaveWritten = true
                    let created = try send(AEEventID(kAECreateElement), [
                        AEKeyword(keyAEObjectClass): .init(typeCode: 0x6E6F7465), // note
                        AEKeyword(keyAEInsertHere): folder,
                        AEKeyword(keyAEPropData): properties,
                    ])
                    readStage = .readback
                    noteID = try text(0x49442020, of: created)
                }
                guard let noteID, !noteID.isEmpty else {
                    throw Failure(message: L10n.text("notes.saved_note_missing"))
                }
                let note = try object(0x6E6F7465, form: OSType(formUniqueID), key: .init(string: noteID))
                if request.managedConfirmation {
                    let (source, body) = try readManaged(note)
                    guard source.id == noteID else { throw NotesHistoryError.response }
                    return Response(version: 1, requestID: request.requestID, status: "ok", noteID: noteID,
                        folderID: source.folderID, plaintext: body.text, sources: [source], sourceBody: body)
                }
                let actualFolder = try property(0x636E7472, of: note) // cntr
                return Response(version: 1, requestID: request.requestID, status: "ok", noteID: noteID,
                    folderID: try text(0x49442020, of: actualFolder), plaintext: try text(0x74657874, of: note))
            } catch is CancellationError {
                guard !mayHaveWritten else {
                    return Response(version: 1, requestID: request.requestID, status: "uncertain")
                }
                throw CancellationError()
            } catch NotesHistoryError.stale {
                guard !mayHaveWritten else {
                    return Response(version: 1, requestID: request.requestID, status: "uncertain")
                }
                throw NotesHistoryError.stale
            } catch {
                let failure = error as? Failure
                let nativeError = error as NSError
                let code = failure?.osStatus
                    ?? (nativeError.domain == NSOSStatusErrorDomain ? nativeError.code : nil)
                let message: String
                if code == -1743 {
                    message = L10n.text("notes.automation_denied", -1743)
                } else if code == -1728 {
                    message = L10n.text("notes.destination_missing", -1728)
                } else if let code { message = "\(error.localizedDescription) (\(code))" }
                else { message = error.localizedDescription }
                return Response(version: 1, requestID: request.requestID, status: mayHaveWritten ? "uncertain" : "failed",
                               message: message, osStatus: code)
            }
        }
        return try await withTaskCancellationHandler {
            try await operation.value
        } onCancel: {
            operation.cancel()
        }
    }
}
