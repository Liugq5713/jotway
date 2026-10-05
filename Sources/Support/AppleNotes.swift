import AppKit
import Carbon

/// 通过备忘录公开的 Apple Event 接口保存与回读；正文始终作为数据传递。
enum AppleNotes {
    struct Destination: Codable, Equatable, Sendable, Identifiable {
        let id: String
        let name: String
    }

    struct Content: Equatable, Sendable {
        let html: String
        let plaintext: String
    }

    struct Request: Sendable {
        let requestID: String
        let operation: String
        var folderID: String?
        var noteID: String?
        var html: String?
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
        if let failure = error as? ActionFailure {
            guard let status = failure.osStatus, [-1743, -1728].contains(status) else { return failure }
            return actionFailure(osStatus: status, operation: operation)
        }
        if let failure = error as? Failure {
            if failure.kind == .launch {
                return ActionFailure(localized: "error.notes.launch_failed", code: .unavailable,
                                     osStatus: failure.osStatus)
            }
            return actionFailure(osStatus: failure.osStatus, operation: operation)
        }
        let error = error as NSError
        return actionFailure(osStatus: error.domain == NSOSStatusErrorDomain ? error.code : nil,
                             operation: operation)
    }

    private static func actionFailure(osStatus: Int?, operation: String,
                                      mayHaveWritten: Bool = false) -> ActionFailure {
        switch osStatus {
        case -1743:
            return ActionFailure(localized: "error.notes.automation_denied", code: .configuration,
                                 osStatus: osStatus)
        case -1728:
            return ActionFailure(localized: "error.notes.destination_missing", code: .configuration,
                                 osStatus: osStatus)
        default:
            let key = operation == "folders" ? "error.notes.folders_failed"
                : mayHaveWritten ? "error.notes.save_uncertain" : "error.notes.save_failed"
            return ActionFailure(localized: key, code: osStatus == -1712 ? .timeout : .processFailed,
                                 osStatus: osStatus,
                                 executionOutcome: mayHaveWritten || (operation == "create" && osStatus == nil) ? .unknown : nil)
        }
    }

    /// Title and original body are separate: deriving a title never consumes an original line.
    /// A span inside pre prevents HTML's special handling of a newline immediately after <pre>.
    static func content(fromPlainText text: String, supplement: NotesSupplement = .empty,
                        tags: [String] = []) -> Content {
        let original = normalizedLines(text)
        let title = original.split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? "Jotway"
        func preservedBlock(_ value: String, region: String) -> String {
            "<pre data-jotway-region=\"\(region)\" style=\"font-family: -apple-system, Helvetica, sans-serif; font-size: 14px; white-space: pre-wrap; overflow-wrap: anywhere; margin: 0;\"><span>\(escapedHTML(value))</span></pre>"
        }
        // Native HTML import coalesces a block boundary with the body's first newline.
        // An explicit separator prevents that boundary from consuming an original blank line.
        var html = "<div>\(escapedHTML(title))</div><div><br></div>" + preservedBlock(original, region: "original")
        var plaintext = title + "\n\n" + original
        let items = supplement.items.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !items.isEmpty {
            let heading = L10n.text("action.notes.supplement.heading")
            let additions = items.map { item in
                let label = L10n.text("action.notes.supplement.\(item.kind.rawValue)")
                return label + ": " + normalizedLines(item.text)
            }.joined(separator: "\n\n")
            html += "<hr><div><b>\(escapedHTML(heading))</b></div>" + preservedBlock(additions, region: "supplement")
            plaintext += "\n\n" + heading + "\n" + additions
        }
        // Existing original tags remain untouched. Only the appended collection is normalized/deduplicated.
        var seen = Set(original.split(whereSeparator: { $0.isWhitespace }).map(String.init))
        let appendedTags = (tags + supplement.tags).compactMap { raw -> String? in
            let cleaned = cleanActionTag(raw)
            guard !cleaned.isEmpty else { return nil }
            let token = "#" + cleaned
            return seen.insert(token).inserted ? token : nil
        }
        if !appendedTags.isEmpty {
            let value = appendedTags.joined(separator: " ")
            html += "<div><br></div>" + preservedBlock(value, region: "tags")
            plaintext += "\n\n" + value
        }
        return Content(html: html, plaintext: plaintext + "\n")
    }

    private static func normalizedLines(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    private static func escapedHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    @MainActor
    static func run(_ request: Request) async throws -> Response {
        try Task.checkCancellation()
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
        // AESend 等待不占用主线程，关窗不会取消外部写入。超时后绝不自动重发。
        return await Task.detached(priority: .userInitiated) {
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
            func send(_ command: AEEventID, _ parameters: [AEKeyword: NSAppleEventDescriptor]) throws -> NSAppleEventDescriptor {
                let event = NSAppleEventDescriptor(eventClass: AEEventClass(kAECoreSuite), eventID: command,
                    targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
                for (key, value) in parameters { event.setParam(value, forKeyword: key) }
                let reply = try event.sendEvent(options: [.waitForReply, .canInteract], timeout: 120)
                if let code = reply.paramDescriptor(forKeyword: AEKeyword(keyErrorNumber))?.int32Value, code != 0 {
                    let message = reply.paramDescriptor(forKeyword: AEKeyword(keyErrorString))?.stringValue
                        ?? L10n.text("notes.operation_failed")
                    throw NSError(domain: NSOSStatusErrorDomain, code: Int(code), userInfo: [NSLocalizedDescriptionKey: message])
                }
                guard let result = reply.paramDescriptor(forKeyword: AEKeyword(keyDirectObject)) else {
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
                    let defaultAccount = try optionalDefault { try property(0x64666163, of: .null()) } // dfac
                    let defaultAccountID = try defaultAccount.flatMap { account in
                        try optionalDefault { try property(0x49442020, of: account) }?.stringValue // ID
                    }
                    var folders: [Destination] = []
                    var preferredFolderIDs: [String] = []
                    for account in try elements(0x61636374) { // acct
                        let accountID = try text(0x49442020, of: account) // ID
                        let accountName = try text(0x706E616D, of: account) // pnam
                        if let defaultFolder = try optionalDefault({ try property(0x64666F6C, of: account) }), // dfol
                           let folderID = try optionalDefault({ try property(0x49442020, of: defaultFolder) })?.stringValue {
                            if accountID == defaultAccountID { preferredFolderIDs.insert(folderID, at: 0) }
                            else { preferredFolderIDs.append(folderID) }
                        }
                        for folder in try elements(0x63666F6C, in: account) { // cfol
                            folders.append(try Destination(id: text(0x49442020, of: folder),
                                name: accountName + " / " + text(0x706E616D, of: folder)))
                        }
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
                    mayHaveWritten = true
                    let created = try send(AEEventID(kAECreateElement), [
                        AEKeyword(keyAEObjectClass): .init(typeCode: 0x6E6F7465), // note
                        AEKeyword(keyAEInsertHere): folder,
                        AEKeyword(keyAEPropData): properties,
                    ])
                    noteID = try text(0x49442020, of: created)
                }
                guard let noteID, !noteID.isEmpty else {
                    throw Failure(message: L10n.text("notes.saved_note_missing"))
                }
                let note = try object(0x6E6F7465, form: OSType(formUniqueID), key: .init(string: noteID))
                let actualFolder = try property(0x636E7472, of: note) // cntr
                return Response(version: 1, requestID: request.requestID, status: "ok", noteID: noteID,
                    folderID: try text(0x49442020, of: actualFolder), plaintext: try text(0x74657874, of: note))
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
        }.value
    }
}
