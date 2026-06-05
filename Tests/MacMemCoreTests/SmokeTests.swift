import XCTest
@testable import MacMemCore

final class ModelsTests: XCTestCase {
    func testSnapshotIsCodableRoundTrip() throws {
        let snap = MemorySnapshot(
            topApps: [AppGroup(name: "Brave", bundleID: "com.brave.Browser",
                               totalFootprintBytes: 1234, processCount: 3, pids: [1, 2, 3])],
            appsStatus: .ok,
            unreadableProcessCount: 0,
            swap: SwapInfo(totalBytes: 100, usedBytes: 40, freeBytes: 60, swapIns: 5, swapOuts: 2),
            swapCulprits: [SwapCulprit(appName: "Brave", bundleID: "com.brave.Browser",
                                       score: 9.0, confidence: .medium)],
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
