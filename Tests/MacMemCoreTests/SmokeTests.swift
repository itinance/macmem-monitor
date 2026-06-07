import XCTest
@testable import MacMemCore

final class ExitCodeTests: XCTestCase {
    private func snap(apps: SectionStatus, swap: SectionStatus) -> MemorySnapshot {
        MemorySnapshot(topApps: [], appsStatus: apps, unreadableProcessCount: 0,
                       swap: nil, compressedUsers: [], swapStatus: swap,
                       topTabs: [], tabsStatus: .ok)
    }

    func testBothErrorSectionsExitsNonZero() {
        XCTAssertEqual(snapshotExitCode(snap(apps: .error, swap: .error)), 1)
    }

    func testOnlyAppsErrorExitsZero() {
        XCTAssertEqual(snapshotExitCode(snap(apps: .error, swap: .ok)), 0)
    }

    func testOnlySwapErrorExitsZero() {
        XCTAssertEqual(snapshotExitCode(snap(apps: .ok, swap: .error)), 0)
    }

    func testPartialExitsZero() {
        XCTAssertEqual(snapshotExitCode(snap(apps: .partial, swap: .partial)), 0)
    }

    func testAllOkExitsZero() {
        XCTAssertEqual(snapshotExitCode(snap(apps: .ok, swap: .ok)), 0)
    }

    func testTabsErrorAloneDoesNotAffectExitCode() {
        let s = MemorySnapshot(topApps: [], appsStatus: .ok, unreadableProcessCount: 0,
                               swap: nil, compressedUsers: [], swapStatus: .ok,
                               topTabs: [], tabsStatus: .error)
        XCTAssertEqual(snapshotExitCode(s), 0)
    }
}

final class ModelsTests: XCTestCase {
    func testSnapshotIsCodableRoundTrip() throws {
        let snap = MemorySnapshot(
            topApps: [AppGroup(name: "Brave", bundleID: "com.brave.Browser",
                               totalFootprintBytes: 1234, processCount: 3, pids: [1, 2, 3])],
            appsStatus: .ok,
            unreadableProcessCount: 0,
            swap: SwapInfo(totalBytes: 100, usedBytes: 40, freeBytes: 60, swapIns: 5, swapOuts: 2),
            compressedUsers: [CompressedMemoryEntry(appName: "Brave", bundleID: "com.brave.Browser",
                                                    compressedBytes: 40)],
            swapStatus: .ok,
            topTabs: [BrowserTab(browser: "Brave", title: "Example", url: "https://example.com",
                                 estimatedBytes: nil, confidence: .low)],
            tabsStatus: .partial
        )
        let data = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(MemorySnapshot.self, from: data)
        XCTAssertEqual(snap, decoded)
    }
}
