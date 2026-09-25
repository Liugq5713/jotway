import XCTest
import Foundation
@testable import Jotway

@MainActor
final class AIProviderTests: XCTestCase {
    private func preferences() throws -> UserDefaults {
        let suite = "Jotway.ARCH02.\(UUID())"
        let value = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { value.removePersistentDomain(forName: suite) }
        return value
    }

    func testEmptyRegistrationsKeepBasicRecordsAndSavedPreferences() throws {
        let preferences = try preferences(), repo = LauncherStore.inMemory()
        preferences.set("external", forKey: "plugin.ai.source")
        preferences.set("model-b", forKey: "plugin.ai.externalModel")
        let app = AppState(repository: repo, preferences: preferences, aiSources: [])
        let session = app.makeLauncherSession(catalog: ApplicationCatalog(applications: []))
        session.updateInput("未发送的原文")
        let draft = session.draft
        XCTAssertEqual(app.aiSource, "external")
        XCTAssertThrowsError(try app.aiRequestConfiguration())
        XCTAssertEqual(session.draft, draft)
        XCTAssertEqual(preferences.string(forKey: "plugin.ai.externalModel"), "model-b")
        app.aiSources = [AIProviderPlugin.Source(id: "external", title: "合成来源",
            models: [(id: "model-a", title: "A"), (id: "model-b", title: "B")],
            modelPreferenceKey: "plugin.ai.externalModel", detail: "",
            version: { "external/\($0 ?? "none")/v1" },
            configure: { _ in .init(version: "external/model-b/v1", modelID: "mock/model") { request in
                    .init(result: request.content, error: nil, modelID: "mock/model")
                }
            })]
        XCTAssertEqual(app.aiModel, "model-b")
        XCTAssertEqual(app.aiSourceVersion, "external/model-b/v1:0")
    }

    func testUnknownSourceAndRemovedSourceNeverFallbackOrRunOnRegistration() async throws {
        let preferences = try preferences(), probe = SourceProbe()
        preferences.set("optional-source", forKey: "plugin.ai.source")
        let source = AIProviderPlugin.Source(id: "optional-source", title: "合成来源", detail: "",
            version: { _ in "optional/v1" }, configure: { _ in
                .init(version: "optional/v1", modelID: "mock/model") { request in
                    await probe.respond(request)
                }
            })
        let app = AppState(repository: .inMemory(), preferences: preferences, aiSources: [])
        let provider = AIProviderPlugin(configuration: { try app.aiRequestConfiguration() })
        XCTAssertEqual(app.aiSource, "optional-source")
        XCTAssertThrowsError(try provider.generator())
        app.aiSources = [source]
        let frozen = try provider.generator()
        app.aiSources = []
        XCTAssertThrowsError(try provider.generator())
        XCTAssertEqual(preferences.string(forKey: "plugin.ai.source"), "optional-source")
        // A request already frozen before removal remains bound to that exact implementation.
        let answer = try await frozen("frozen", "fixed")
        XCTAssertEqual(answer, "frozen")
        XCTAssertEqual(frozen.modelID, "mock/model")
        app.aiSources = [source]
        var requests = await probe.requests
        XCTAssertEqual(requests.map(\.content), ["frozen"])
        let next = try provider.generator()
        _ = try await next("explicit-next", "fixed")
        requests = await probe.requests
        XCTAssertEqual(requests.map(\.content), ["frozen", "explicit-next"])
    }

}

private actor SourceProbe {
    var requests: [AIProviderPlugin.Request] = []
    func respond(_ request: AIProviderPlugin.Request) -> AIProviderPlugin.Response {
        requests.append(request)
        return .init(result: request.content, error: nil, modelID: "mock/model")
    }
}
