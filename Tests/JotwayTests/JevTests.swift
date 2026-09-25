import Foundation
import XCTest
@testable import Jotway

/// 合成协议/路由检查，不测模型准确率，不读取 Keychain，也不发送到外部服务。
@MainActor
final class JevTests: XCTestCase {
    nonisolated private static func choice(_ selected: String, options: [String], confidence: Double = 1) -> [String: Any] {
        ["type": "choice", "choice": selected, "confidence": confidence,
         "probabilities": Dictionary(uniqueKeysWithValues: options.map { ($0, $0 == selected ? 1.0 : 0.0) })]
    }

    nonisolated private static func outer(_ selected: String, confidence: Double = 1) -> [String: Any] {
        choice(selected, options: Array(Jev.outerOperationCriteria.keys), confidence: confidence)
    }

    nonisolated private static func response(_ answers: [String: Any], model: String = "jev-1.13.0") throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "model": model, "answers": answers, "usage": ["input_tokens": 400, "output_tokens": 50]
        ])
    }

    private func answers(outer: String, scope: Any? = nil, current: Any = 1.0) -> [String: Any] {
        var values: [String: Any] = [
            "current_request": ["type": "noul", "noul": current],
            "outer_operation": Self.outer(outer)
        ]
        if let scope { values["task_scope"] = scope }
        return values
    }

    func testRequestUsesOneNoulThreeChoicesWithoutApplicationCandidates() throws {
        let draft = "合成草稿\n用 Google 搜明天计划"
        // capture_kind 的选项现由注入的存储 action 动态生成（键 = action id）。
        let capture = [Jev.CaptureOption(id: "apple-calendar", criteria: "日程"),
                       Jev.CaptureOption(id: "apple-reminders", criteria: "待办"),
                       Jev.CaptureOption(id: "apple-notes", criteria: "备忘")]
        let request = try Jev.makeRequest(text: draft, apiKey: "synthetic-key", capture: capture)
        XCTAssertEqual(request.url?.absoluteString, "https://api.typesafe.ai/v1/systemone")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.timeoutInterval, 1.5)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(Set(body.keys), ["model", "state", "questions"])
        XCTAssertEqual(body["model"] as? String, "jev-latest")
        XCTAssertEqual(body["state"] as? [String: String], ["draft_text": draft])
        let questions = try XCTUnwrap(body["questions"] as? [String: [String: Any]])
        XCTAssertEqual(Set(questions.keys), ["current_request", "outer_operation", "task_scope", "capture_kind"])
        XCTAssertEqual(questions["current_request"]?["type"] as? String, "noul")
        XCTAssertEqual(Set(try XCTUnwrap(questions["current_request"]?["criteria"] as? [String: String]).keys), ["true", "false"])
        XCTAssertEqual(questions["outer_operation"]?["type"] as? String, "choice")
        XCTAssertEqual(questions["task_scope"]?["type"] as? String, "choice")
        XCTAssertEqual(questions["capture_kind"]?["type"] as? String, "choice")
        // capture_kind 的 criteria 键 = 注入的 action id（动态），不再是固定 event/reminder/note。
        XCTAssertEqual(Set(try XCTUnwrap(questions["capture_kind"]?["criteria"] as? [String: String]).keys),
                       ["apple-calendar", "apple-reminders", "apple-notes"])
        XCTAssertNil(questions["app_target"])
        let definition = try XCTUnwrap(JSONSerialization.jsonObject(with: Jev.ruleDefinitionData()) as? [String: Any])
        XCTAssertEqual(definition["version"] as? String, Jev.ruleVersion)
        // 三道固定问逐字复现实发；capture_kind 动态，导出只留框架，故比对时剔除（约束 1 放宽后的不变量）。
        let exportedQuestions = try XCTUnwrap((definition["questions"] as? [String: Any]))
        let fixedKeys = ["current_request", "outer_operation", "task_scope"]
        XCTAssertEqual(exportedQuestions.filter { fixedKeys.contains($0.key) } as NSDictionary,
                       questions.filter { fixedKeys.contains($0.key) } as NSDictionary,
                       "三道固定问的导出必须逐字复现实发")
        XCTAssertEqual(try XCTUnwrap(exportedQuestions["capture_kind"] as? [String: Any])["type"] as? String, "choice",
                       "capture_kind 导出保留结构，criteria 为动态占位")
        XCTAssertNil(definition["applicationInstructions"])
        XCTAssertNil(definition["applicationCriteriaTemplate"])
        XCTAssertNil(JevDiagnostics.Action(rawValue: "removed-action"), "在线诊断只接受当前固定 action 集合")
        let historicalAction = try JSONDecoder().decode(JevDiagnostics.Action.self, from: Data(#""retired-action""#.utf8))
        let historicalReason = try JSONDecoder().decode(JevDiagnostics.Reason.self, from: Data(#""retired-reason""#.utf8))
        XCTAssertEqual(historicalAction, .unknown)
        XCTAssertEqual(historicalReason, .unknown)
        XCTAssertEqual(String(data: try JSONEncoder().encode(historicalAction), encoding: .utf8), #""unknown""#,
                       "历史未知值只能收敛为固定非执行状态，不能写入任意原值")
        XCTAssertEqual(JevDiagnostics().bounded.ruleVersion, Jev.ruleVersion)
        XCTAssertEqual(JevDiagnostics(ruleVersion: "jev-intent-v2").bounded.ruleVersion, "jev-intent-v2",
                       "Historical logs must retain their original rules")
    }

    func testHTTPClientUsesInjectedSessionOnceAndConnectionTestContainsOnlyFixedText() async throws {
        let recognition = try Self.response(answers(outer: "google_search"))
        let session = self.session { request in
            XCTAssertEqual(request.url, Jev.endpoint)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-key")
            return (200, [:], recognition)
        }
        let result = try await Jev.recognize(text: "合成当前草稿", apiKey: "synthetic-key", session: session)
        XCTAssertEqual(result, Jev.Decision(action: .google, model: "jev-1.13.0"))

        let connection = try Self.response(["connection_check": ["type": "noul", "noul": 0.8]])
        let testSession = self.session { request in
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JevTestURLProtocol.body(request)) as? [String: Any])
            XCTAssertEqual(object["state"] as? String, "This is a non-private Jotway connection test.")
            XCTAssertEqual(Set(try XCTUnwrap(object["questions"] as? [String: Any]).keys), ["connection_check"])
            return (200, [:], connection)
        }
        let testedModel = try await Jev.testConnection(apiKey: "synthetic-key", session: testSession)
        XCTAssertEqual(testedModel, "jev-1.13.0")
    }

    private func session(_ handler: @escaping JevTestURLProtocol.Handler) -> URLSession {
        let id = UUID().uuidString
        JevTestURLProtocol.register(id: id, handler: handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [JevTestURLProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Jotway-Jev-Test": id]
        let session = URLSession(configuration: configuration)
        addTeardownBlock {
            session.invalidateAndCancel()
            JevTestURLProtocol.unregister(id: id)
        }
        return session
    }
}

private final class JevTestURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (Int, [String: String], Data)
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]

    static func register(id: String, handler: @escaping Handler) { lock.withLock { handlers[id] = handler } }
    static func unregister(id: String) { lock.withLock { handlers[id] = nil } }

    static func body(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let id = request.value(forHTTPHeaderField: "X-Jotway-Jev-Test") ?? ""
        let handler = Self.lock.withLock { Self.handlers[id] }
        do {
            guard let handler else { throw URLError(.unsupportedURL) }
            let (status, headers, data) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
