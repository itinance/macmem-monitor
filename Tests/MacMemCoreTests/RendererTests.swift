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
            compressedUsers: [CompressedMemoryEntry(appName: "Brave Browser", bundleID: "com.brave.Browser",
                                                    compressedBytes: 536_870_912)],
            compressedUnreadableCount: 3,
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
        XCTAssertTrue(out.contains("512.0 MB"),        // measured compressed bytes per entry
                      "swap section should show the measured compressed MB figure")
        XCTAssertTrue(out.contains("Brave Browser"),   // app name in compressed list
                      "compressed memory entry should show the app name")
        XCTAssertTrue(out.contains("[measured]"),       // measured marker (NOT ~ or confidence)
                      "compressed memory rows must carry [measured] marker")
        XCTAssertFalse(out.contains("~512"),           // NO estimate tilde before the 512 MB figure
                       "compressed memory rows must NOT contain ~ prefix (these are measured, not estimated)")
        XCTAssertFalse(out.contains("medium"),         // NO old confidence label
                       "compressed memory rows must NOT contain confidence labels like 'medium'")
        XCTAssertTrue(out.contains("could not be read from top"),
                      "coverage footer should appear when compressedUnreadableCount > 0")
        XCTAssertFalse(out.lowercased().contains("sudo"),
                       "compressed section footer must not mention sudo")
        // FINDING 4: confidence label must appear on estimated tab rows
        XCTAssertTrue(out.contains("[low]"),
                      "estimated tab rows should carry a [low] confidence label")
    }

    // FINDING 4: tab rows with no estimate must NOT carry a confidence label
    func testTabRowWithNoEstimateHasNoConfidenceLabel() {
        let snap = MemorySnapshot(
            topApps: [], appsStatus: .ok, unreadableProcessCount: 0,
            swap: nil, compressedUsers: [], swapStatus: .ok,
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
            swap: nil, compressedUsers: [], swapStatus: .ok,
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
            swap: nil, compressedUsers: [], swapStatus: .ok,
            topTabs: [], tabsStatus: .ok)
        let out = TextRenderer.render(snap)
        XCTAssertTrue(out.lowercased().contains("sudo"),
                      "apps partial message should mention sudo")
        XCTAssertTrue(out.contains("3"),
                      "apps partial message should include the unreadable count")
    }

    // NIT 2: partial status with non-empty tabs — both tab rows AND the status note must appear
    func testTabsPartialWithTabsShowsBothTabRowAndNote() {
        let snap = MemorySnapshot(
            topApps: [], appsStatus: .ok, unreadableProcessCount: 0,
            swap: nil, compressedUsers: [], swapStatus: .ok,
            topTabs: [BrowserTab(browser: "Brave Browser", title: "Loaded Page",
                                 url: "https://loaded.com", estimatedBytes: nil, confidence: .low)],
            tabsStatus: .partial)
        let out = TextRenderer.render(snap)
        XCTAssertTrue(out.contains("https://loaded.com"),
                      "tab rows should still render when tabsStatus is .partial")
        XCTAssertTrue(out.contains("some browsers could not be read"),
                      "partial note must appear even when some tabs were returned")
    }

    // FINDING B: column alignment — memory string must start at the same offset
    // for a short name and a long (truncated) name.
    func testTopAppsColumnsAlignAcrossShortAndLongNames() {
        let shortName = "Safari"
        let longName = "com.apple.WebKit.WebContent.XPC.SuperLongProcessNameThatExceedsColumn"
        let snap = MemorySnapshot(
            topApps: [
                AppGroup(name: shortName, bundleID: nil,
                         totalFootprintBytes: 123_456_789, processCount: 1, pids: [1]),
                AppGroup(name: longName, bundleID: nil,
                         totalFootprintBytes: 987_654_321, processCount: 2, pids: [2, 3])
            ],
            appsStatus: .ok, unreadableProcessCount: 0,
            swap: nil, compressedUsers: [], swapStatus: .ok,
            topTabs: [], tabsStatus: .ok)
        let out = TextRenderer.render(snap)
        let lines = out.split(separator: "\n", omittingEmptySubsequences: false)
        // Find the two app rows (they follow "== TOP APPS ==")
        let appLines = lines.filter { $0.contains(" 1. ") || $0.contains(" 2. ") }
        XCTAssertEqual(appLines.count, 2, "Expected two app rows")
        guard appLines.count == 2 else { return }

        // The memory substring (e.g. "117.7 MB") should start at the same character offset.
        func memOffset(_ line: Substring) -> Int? {
            // Memory field starts after the name+padding column (after the double-space separator)
            // Find the first digit of the memory value by searching after the name column.
            // We look for the byte-value pattern: digits followed by space then a unit letter.
            // A simpler proxy: find the position of the last run of spaces before the memory value.
            // Actually just assert the columns are equal by finding the index of "MB" or "GB" or "KB"
            // and subtracting the unit width back to the start of the number.
            // Easiest: find the position of the two-space separator that precedes the memory column.
            if let range = line.range(of: "  ", options: .backwards,
                                      range: line.startIndex..<(line.lastIndex(of: "(") ?? line.endIndex)) {
                return line.distance(from: line.startIndex, to: range.lowerBound)
            }
            return nil
        }

        let offset1 = memOffset(appLines[0])
        let offset2 = memOffset(appLines[1])
        XCTAssertNotNil(offset1)
        XCTAssertNotNil(offset2)
        XCTAssertEqual(offset1, offset2,
                       "Memory column should start at the same offset for short and long names")

        // Long name should be truncated with "…"
        XCTAssertTrue(appLines[1].contains("…"),
                      "Name longer than the column width should be truncated with '…'")
    }

    // Fix 7 (Major): --no-swap must suppress the SWAP section entirely.
    func testRenderWithNoSwapOmitsSwapSection() {
        let out = TextRenderer.render(fixture(), includeSwap: false)
        XCTAssertFalse(out.contains("== SWAP =="), "SWAP section must not appear when includeSwap: false")
    }

    // Fix 7 (Major): --no-tabs must suppress the BROWSER TABS section entirely.
    func testRenderWithNoTabsOmitsTabsSection() {
        let out = TextRenderer.render(fixture(), includeTabs: false)
        XCTAssertFalse(out.contains("BROWSER TABS"), "BROWSER TABS section must not appear when includeTabs: false")
    }

    func testJSONRendererIsValidAndRoundTrips() throws {
        let json = try JSONRenderer.render(fixture())
        let decoded = try JSONDecoder().decode(MemorySnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(decoded, fixture())
    }
}
