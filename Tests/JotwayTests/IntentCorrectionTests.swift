import XCTest
@testable import Jotway

final class IntentCorrectionTests: XCTestCase {
    private func makeCorrection(_ index: Int, at date: Date) -> IntentCorrection {
        IntentCorrection(correctedAt: date, text: "draft-\(index)",
            jevTargetID: "removed-action", jevLabel: "已移除目标",
            chosenTargetID: "apple-reminders", chosenLabel: "存到提醒事项")
    }

    func testSaveFetchAndClearRoundTrips() throws {
        let repository = LauncherStore.inMemory()
        let sample = makeCorrection(1, at: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertTrue(try repository.saveIntentCorrection(sample))
        // 同 id 不重复插入。
        XCTAssertFalse(try repository.saveIntentCorrection(sample))
        let fetched = try repository.recentIntentCorrections()
        XCTAssertEqual(fetched, [sample])
        try repository.clearIntentCorrections()
        XCTAssertEqual(try repository.intentCorrectionCount(), 0)
    }
}
