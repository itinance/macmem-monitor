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
        // FINDING 4: confidence label must appear on estimated tab rows
        XCTAssertTrue(out.contains("[low]"),
                      "estimated tab rows should carry a [low] confidence label")
    }

    // FINDING 4: tab rows with no estimate must NOT carry a confidence label
    func testTabRowWithNoEstimateHasNoConfidenceLabel() {
        let snap = MemorySnapshot(
            topApps: [], appsStatus: .ok, unreadableProcessCount: 0,
            swap: nil, swapCulprits: [], swapStatus: .ok,
            topTabs: [BrowserTab(browser: "Brave Browser", title: "No Estimate",
                                 url: "https://noest.com", estimatedBytes: nil, confidence: .low)],
            tabsStatus: .ok)
        let out = TextRenderer.render(snap)
        XCTAssertFalse(out.contains("[low]"),
                       "tab rows without an estimate should not carry a confidence label")
    }

    // FINDING 7: partial message for tabs section must not mention "sudo" or unreadable counts
    func testTabsPartialMessageIsContextAppropriate() {
        let snap = MemorySnapshot(
            topApps: [], appsStatus: .ok, unreadableProcessCount: 0,
            swap: nil, swapCulprits: [], swapStatus: .ok,
            topTabs: [], tabsStatus: .partial)
        let out = TextRenderer.render(snap)
        XCTAssertTrue(out.contains("partial"), "tabs partial status should say 'partial'")
        XCTAssertFalse(out.lowercased().contains("sudo"),
                       "tabs partial message should not mention sudo")
        XCTAssertFalse(out.contains("not readable"),
                       "tabs partial message should not mention unreadable process counts")
    }

    // FINDING 7: partial message for apps section SHOULD mention sudo / unreadable count
    func testAppsPartialMessageMentionsSudo() {
        let snap = MemorySnapshot(
            topApps: [], appsStatus: .partial, unreadableProcessCount: 3,
            swap: nil, swapCulprits: [], swapStatus: .ok,
            topTabs: [], tabsStatus: .ok)
        let out = TextRenderer.render(snap)
        XCTAssertTrue(out.lowercased().contains("sudo"),
                      "apps partial message should mention sudo")
        XCTAssertTrue(out.contains("3"),
                      "apps partial message should include the unreadable count")
    }

    func testJSONRendererIsValidAndRoundTrips() throws {
        let json = try JSONRenderer.render(fixture())
        let decoded = try JSONDecoder().decode(MemorySnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(decoded, fixture())
    }
}
