import Darwin
import Foundation

/// One background turn over the public app-server protocol. Raw events never enter runtime logs.
struct CodexAppServerSession: Sendable {
    private static let taskModel = "gpt-6-astra"
    private static let taskEffort = "high"

    private enum Stage: Sendable { case initialize, thread, turn, running, finished }
    private var stage = Stage.initialize
    private var buffer = Data()
    private var turnID: String?
    private(set) var threadID: String?
    private(set) var threadName: String?
    private(set) var threadNameRevision = 0
    private(set) var submitted = false
    private(set) var completed = false
    private(set) var finalText = ""
    private(set) var protocolFailed = false

    var finished: Bool { stage == .finished }

    /// Foundation's fixed-length pipe reads can wait for a full buffer, deadlocking the handshake.
    static func readAvailable(from handle: FileHandle) throws -> Data? {
        var bytes = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = Darwin.read(handle.fileDescriptor, &bytes, bytes.count)
            if count > 0 { return Data(bytes.prefix(count)) }
            if count == 0 { return nil }
            if errno != EINTR { throw CocoaError(.fileReadUnknown) }
        }
    }

    static func initialize(version: String) throws -> Data {
        try encode(["id": 1, "method": "initialize", "params": [
            "clientInfo": ["name": "jotway", "title": "Jotway", "version": version]
        ]])
    }

    mutating func consume(_ data: Data, prompt: String, directory: URL,
                          send: (Data) throws -> Void) throws {
        buffer.append(data)
        while !finished, let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            guard line.count <= 8 * 1024 * 1024 else { throw CocoaError(.fileReadCorruptFile) }
            if !line.isEmpty { try receive(line, prompt: prompt, directory: directory, send: send) }
        }
        guard buffer.count <= 8 * 1024 * 1024 else { throw CocoaError(.fileReadCorruptFile) }
    }

    mutating func connectionFailed() {
        protocolFailed = true
        stage = .finished
    }

    private mutating func receive(_ data: Data, prompt: String, directory: URL,
                                 send: (Data) throws -> Void) throws {
        guard let message = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if let method = message["method"] as? String {
            if let id = message["id"] {
                try send(Self.encode(Self.denial(for: method, id: id)))
                return
            }
            guard submitted, let params = message["params"] as? [String: Any],
                  params["threadId"] as? String == threadID else { return }
            switch method {
            case "thread/name/updated":
                threadName = params["threadName"] as? String
                threadNameRevision += 1
            case "turn/started":
                if let turn = params["turn"] as? [String: Any], let id = turn["id"] as? String {
                    try acceptTurn(id)
                }
            case "item/completed":
                guard let id = params["turnId"] as? String, id == turnID,
                      let item = params["item"] as? [String: Any] else { return }
                retainAnswer(item)
            case "turn/completed":
                guard let turn = params["turn"] as? [String: Any], let id = turn["id"] as? String else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                try acceptTurn(id)
                for item in turn["items"] as? [[String: Any]] ?? [] { retainAnswer(item) }
                completed = turn["status"] as? String == "completed"
                stage = .finished
            default: break
            }
            return
        }
        guard let id = message["id"] as? Int, (1...3).contains(id) else { return }
        if message["error"] != nil { throw CocoaError(.fileReadUnknown) }
        guard let result = message["result"] as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        switch (stage, id) {
        case (.initialize, 1):
            try send(Self.encode(["method": "initialized", "params": [:]]))
            stage = .thread
            try send(Self.encode(["id": 2, "method": "thread/start", "params": [
                "cwd": directory.path, "approvalPolicy": "never", "sandbox": "workspace-write",
                "ephemeral": false, "model": Self.taskModel
            ]]))
        case (.thread, 2):
            guard let thread = result["thread"] as? [String: Any],
                  let id = thread["id"] as? String, UUID(uuidString: id) != nil,
                  let source = thread["source"] as? String, ["vscode", "cli"].contains(source) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            threadID = id
            if thread["name"] != nil {
                threadName = thread["name"] as? String
                threadNameRevision += 1
            }
            // A broken connection after this write may still have started work; never retry automatically.
            submitted = true
            stage = .turn
            try send(Self.encode(["id": 3, "method": "turn/start", "params": [
                "threadId": id, "input": [["type": "text", "text": prompt]],
                "model": Self.taskModel, "effort": Self.taskEffort
            ]]))
        case (.turn, 3):
            guard let turn = result["turn"] as? [String: Any], let id = turn["id"] as? String else {
                throw CocoaError(.fileReadCorruptFile)
            }
            try acceptTurn(id)
            stage = .running
        default: break
        }
    }

    private mutating func acceptTurn(_ id: String) throws {
        guard !id.isEmpty, turnID == nil || turnID == id else { throw CocoaError(.fileReadCorruptFile) }
        turnID = id
    }

    private mutating func retainAnswer(_ item: [String: Any]) {
        guard item["type"] as? String == "agentMessage", item["phase"] as? String != "commentary",
              let text = item["text"] as? String else { return }
        finalText = text
    }

    private static func denial(for method: String, id: Any) -> [String: Any] {
        let result: [String: Any]
        switch method {
        case "item/commandExecution/requestApproval", "item/fileChange/requestApproval":
            result = ["decision": "decline"]
        case "item/permissions/requestApproval":
            result = ["permissions": [:], "scope": "turn"]
        case "item/tool/requestUserInput":
            result = ["answers": [:]]
        case "mcpServer/elicitation/request":
            result = ["action": "decline", "content": NSNull()]
        default:
            return ["id": id, "error": ["code": -32601, "message": "Unsupported background request"]]
        }
        return ["id": id, "result": result]
    }

    private static func encode(_ message: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(10)
        return data
    }
}
