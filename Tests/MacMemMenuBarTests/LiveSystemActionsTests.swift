import XCTest
@testable import MacMemMenuBar
@testable import MacMemCore

@MainActor
final class LiveSystemActionsTests: XCTestCase {
    func testCurrentCandidatesAreNonEmpty() throws {
        // A macOS host with a GUI session has apps registered with NSWorkspace (Finder at
        // minimum). Headless CI runners may have none, so skip there rather than fail; when
        // candidates exist they must carry valid pids. (The XCTest runner process is not
        // itself an NSWorkspace app, so we don't assert its own pid.)
        let candidates = LiveSystemActions.currentCandidates()
        try XCTSkipIf(candidates.isEmpty, "No GUI session detected on this runner.")
        XCTAssertTrue(candidates.allSatisfy { $0.pid > 0 },
                      "enumerated candidates should carry valid process identifiers")
    }

    func testQuitUnmatchedGroupReturnsNotPermitted() async {
        // A group that matches no running app cannot be quit.
        let ghost = AppGroup(name: "Ghost", bundleID: "com.nonexistent.ghost.\(UUID().uuidString)",
                             totalFootprintBytes: 1, processCount: 1, pids: [Int32.max - 1])
        let result = await LiveSystemActions().quit(app: ghost)
        XCTAssertEqual(result, .notPermitted)
    }
}
