import XCTest
@testable import MacMemMenuBar
@testable import MacMemCore

@MainActor
final class LiveSystemActionsTests: XCTestCase {
    func testCurrentCandidatesAreNonEmpty() {
        // A macOS host running these tests always has GUI apps registered with NSWorkspace
        // (Finder at minimum), so the candidate enumeration must be non-empty. (The XCTest
        // runner process is not itself an NSWorkspace app, so we don't assert its own pid.)
        XCTAssertFalse(LiveSystemActions.currentCandidates().isEmpty,
                       "should enumerate at least one running GUI application")
    }

    func testQuitUnmatchedGroupReturnsNotPermitted() async {
        // A group that matches no running app cannot be quit.
        let ghost = AppGroup(name: "Ghost", bundleID: "com.nonexistent.ghost.\(UUID().uuidString)",
                             totalFootprintBytes: 1, processCount: 1, pids: [Int32.max - 1])
        let result = await LiveSystemActions().quit(app: ghost)
        XCTAssertEqual(result, .notPermitted)
    }
}
