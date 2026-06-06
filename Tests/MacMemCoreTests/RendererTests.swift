import XCTest
@testable import MacMemCore

final class RendererTests: XCTestCase {
    private func fixture() -> MemorySnapshot {
        MemorySnapshot(
            topApps: [AppGroup(name: "Brave Browser", bundleID: "com.brave.Browser",
                               totalFootprintBytes: 1_572_864, processCount: 3, pids: [1, 2, 3])],
            appsStatus: .ok, unreadableProcessCount: 0,
            swap: SwapInfo(totalBytes: 2_147_483_648, usedBytes: 1_073_741_824,
                           freeBytes: 1_073_741_824, swapIns: 10, swapOuts: 4),
            swapCulprits: [SwapCulprit(appName: "Brave Browser", bundleID: "com.brave.Browser",
                                       score: 100, confidence: .medium)],
            swapStatus: .ok,
            topTabs: [BrowserTab(browser: "Brave Browser", title: "Example",
                                 url: "https://example.com", estimatedBytes: 1_048_576, confidence: .low)],
            tabsStatus: .ok)
    }

    func testTextRendererContainsAllSections() {
        let out = TextRenderer.render(fixture())
        XCTAssertTrue(out.contains("TOP APPS"))
        XCTAssertTrue(out.contains("Brave Browser"))
        XCTAssertTrue(out.contains("1.5 MB"))
        XCTAssertTrue(out.contains("SWAP"))
        XCTAssertTrue(out.contains("1.0 GB"))
        XCTAssertTrue(out.contains("BROWSER TABS"))
        XCTAssertTrue(out.contains("https://example.com"))
        XCTAssertTrue(out.contains("~"))               // estimate marker
        XCTAssertTrue(out.contains("medium"))          // culprit confidence
    }

    func testJSONRendererIsValidAndRoundTrips() throws {
        let json = try JSONRenderer.render(fixture())
        let decoded = try JSONDecoder().decode(MemorySnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(decoded, fixture())
    }
}
