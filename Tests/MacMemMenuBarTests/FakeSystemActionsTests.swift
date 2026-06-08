import XCTest
@testable import MacMemMenuBar
@testable import MacMemCore

@MainActor final class FakeSystemActionsTests: XCTestCase {
    private func group(_ name: String) -> AppGroup {
        AppGroup(name: name, bundleID: "com.x", totalFootprintBytes: 1, processCount: 1, pids: [1])
    }

    func testRecordsQuitAndReturnsScriptedResult() async {
        let fake = FakeSystemActions()
        fake.quitResult = .failed("boom")
        let result = await fake.quit(app: group("Brave Browser"))
        XCTAssertEqual(result, .failed("boom"))
        XCTAssertEqual(fake.quitCalls.map(\.name), ["Brave Browser"])
    }

    func testRecordsPurge() async {
        let fake = FakeSystemActions()
        _ = await fake.purge()
        XCTAssertEqual(fake.purgeCallCount, 1)
    }

    func testRecordsRevealAndCopy() {
        let fake = FakeSystemActions()
        fake.revealInActivityMonitor(app: group("A"))
        fake.copySnapshot("hello")
        XCTAssertEqual(fake.revealCalls.map(\.name), ["A"])
        XCTAssertEqual(fake.copiedText, "hello")
    }
}
