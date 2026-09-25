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

        /// 校验一次「存入备忘录」写入是否完整落地：状态 ok、拿到 noteID、落在预期文件夹、
        /// 正文逐字一致。启动器路径（AppleNotesAction / 设置验证）共用。
        func confirms(requestID: String, folderID: String, plaintext: String) -> Bool {
            version == 1 && status == "ok" && self.requestID == requestID
                && noteID?.isEmpty == false && self.folderID == folderID
                && self.plaintext == plaintext
        }
    }

    struct Failure: LocalizedError {
        let message: String
        /// 仅能证明请求根本未送达的 Apple Event 错误可直接重试。
        var notStarted = false
        /// 失败时的 Apple Event OSStatus，用于诊断日志。
        var osStatus: Int? = nil
        var errorDescription: String? { message }
    }

    /// 纯文本 → Notes 内容（启动器路径，不经沉淀层的 Note）：
    /// 首个非空行作标题，其余每行各自成普通段落（div）。不用 pre，故没有等宽灰底块，
    /// 也不再有和标题重复的冗余正文；代价是不保留代码缩进（AI 加工后的正文以散文/要点为主）。
    static func content(fromPlainText text: String) -> Content {
        var lines = normalizedLines(text).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let titleIndex = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            // 全空白：占位标题，无正文。
            return Content(html: "<div>Jotway</div>", plaintext: "Jotway\n")
        }
        let title = lines[titleIndex].trimmingCharacters(in: .whitespaces)
        lines.removeSubrange(0...titleIndex)
        let remainder = lines.joined(separator: "\n")
        // Notes 会在最后一个块后追加一个换行。标题之后无内容时只发标题。
        guard !remainder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Content(html: "<div>\(escapedHTML(title))</div>", plaintext: title + "\n")
        }
        // 每行独立成段，空行用 <br> 占位；普通 div 即正文默认样式，无灰底。
        let bodyHTML = lines.map {
            $0.trimmingCharacters(in: .whitespaces).isEmpty ? "<div><br></div>" : "<div>\(escapedHTML($0))</div>"
        }.joined()
        return Content(html: "<div>\(escapedHTML(title))</div>\(bodyHTML)",
                       plaintext: title + "\n" + remainder + "\n")
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
        if NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Notes").isEmpty {
            let options = NSWorkspace.OpenConfiguration()
            options.activates = false
            options.addsToRecentItems = false
            do {
                _ = try await NSWorkspace.shared.openApplication(
                    at: URL(fileURLWithPath: "/System/Applications/Notes.app"), configuration: options)
            } catch {
                throw Failure(message: L10n.text("notes.launch_failed", error.localizedDescription), notStarted: true)
            }
        }
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
                    var folders: [Destination] = []
                    for account in try elements(0x61636374) { // acct
                        let accountName = try text(0x706E616D, of: account) // pnam
                        for folder in try elements(0x63666F6C, in: account) { // cfol
                            folders.append(try Destination(id: text(0x49442020, of: folder),
                                name: accountName + " / " + text(0x706E616D, of: folder)))
                        }
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
                let code = (error as NSError).code
                let message: String
                if code == -1743 {
                    message = L10n.text("notes.automation_denied", code)
                } else if code == -1728 {
                    message = L10n.text("notes.destination_missing", code)
                } else { message = "\(error.localizedDescription)（\(code)）" }
                return Response(version: 1, requestID: request.requestID, status: mayHaveWritten ? "uncertain" : "failed",
                               message: message, osStatus: code)
            }
        }.value
    }
}
