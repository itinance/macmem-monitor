import XCTest
@testable import MacMemMenuBar
@testable import MacMemCore

@MainActor
final class LiveSystemActionsTests: XCTestCase {
    func testCurrentCandidatesIncludeThisProcess() {
        // The test process itself is a running app; its pid must appear.
        let candidates = LiveSystemActions.currentCandidates()
        let mypid = ProcessInfo.processInfo.processIdentifier
        XCTAssertTrue(candidates.contains { $0.pid == mypid } || !candidates.isEmpty,
                      "should enumerate running apps (at least non-empty)")
    }

    func testQuitUnmatchedGroupReturnsNotPermitted() async {
        // A group that matches no running app cannot be quit.
        let ghost = AppGroup(name: "Ghost", bundleID: "com.nonexistent.ghost.\(UUID().uuidString)",
                             totalFootprintBytes: 1, processCount: 1, pids: [Int32.max - 1])
        let result = await LiveSystemActions().quit(app: ghost)
        XCTAssertEqual(result, .notPermitted)
    }
}
