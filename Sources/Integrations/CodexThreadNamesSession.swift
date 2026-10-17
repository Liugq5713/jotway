import Foundation

struct CodexThreadName: Sendable {
    let threadID: String
    let name: String?
}

/// A metadata-only connection: never creates, resumes, renames, or submits a thread.
struct CodexThreadNamesSession: Sendable {
    private var pending: [Int: String]
    private var initialized = false
    private var buffer = Data()
    private(set) var names: [CodexThreadName] = []
    private(set) var finished = false

    init(threadIDs: [String]) {
        var unique: [String] = []
        for id in threadIDs where UUID(uuidString: id) != nil && !unique.contains(id) {
            unique.append(id)
            if unique.count == 5 { break }
        }
        pending = Dictionary(unique.enumerated().map { ($0.offset + 2, $0.element) }, uniquingKeysWith: { first, _ in first })
    }

    mutating func consume(_ data: Data, send: (Data) throws -> Void) throws {
        buffer.append(data)
        while !finished, let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            guard line.count <= 8 * 1024 * 1024 else { throw CocoaError(.fileReadCorruptFile) }
            if !line.isEmpty { try receive(line, send: send) }
        }
        guard buffer.count <= 8 * 1024 * 1024 else { throw CocoaError(.fileReadCorruptFile) }
    }

    private mutating func receive(_ data: Data, send: (Data) throws -> Void) throws {
        guard let message = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if message["method"] != nil {
            if let id = message["id"] {
                try send(Self.encode(["id": id, "error": ["code": -32601, "message": "Metadata-only client"]]))
            }
            return
        }
        guard let id = message["id"] as? Int else { return }
        if !initialized, id == 1 {
            guard message["error"] == nil, message["result"] is [String: Any] else {
                finished = true
                return
            }
            initialized = true
            try send(Self.encode(["method": "initialized", "params": [:]]))
            for (requestID, threadID) in pending.sorted(by: { $0.key < $1.key }) {
                try send(Self.encode(["id": requestID, "method": "thread/read",
                    "params": ["threadId": threadID, "includeTurns": false]]))
            }
            finished = pending.isEmpty
        } else if initialized, let threadID = pending.removeValue(forKey: id) {
            if message["error"] == nil,
               let result = message["result"] as? [String: Any], let thread = result["thread"] as? [String: Any],
               thread["id"] as? String == threadID, let name = thread["name"], name is String || name is NSNull {
                names.append(CodexThreadName(threadID: threadID, name: name as? String))
            }
            finished = pending.isEmpty
        }
    }

    private static func encode(_ message: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(10)
        return data
    }
}
