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
            browsers: [BrowserMemory(browser: "Brave Browser", totalFootprintBytes: 1_048_576,
                                     processCount: 3,
                                     tabs: [BrowserTab(title: "Example", url: "https://example.com")])],
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
        // The per-browser subheader shows a MEASURED total and carries the [measured] marker.
        XCTAssertTrue(out.contains("across 3 processes"),
                      "browser subheader should show the measured process count")
        XCTAssertFalse(out.contains("(n/a)"),
                       "the fake per-tab estimate column must be gone")
        XCTAssertFalse(out.contains("~"),
                       "no estimate tilde anywhere — tabs show no per-tab memory")
    }

    // A browser whose memory is not attributable (e.g. Safari) shows an honest note,
    // never a fabricated or misleadingly tiny number.
    func testBrowserWithUnattributableMemoryShowsHonestNote() {
        let snap = MemorySnapshot(
            topApps: [], appsStatus: .ok, unreadableProcessCount: 0,
            swap: nil, compressedUsers: [], swapStatus: .ok,
            browsers: [BrowserMemory(browser: "Safari", totalFootprintBytes: nil, processCount: 0,
                                     tabs: [BrowserTab(title: "DI", url: "https://di.fm/")])],
            tabsStatus: .ok)
        let out = TextRenderer.render(snap)
        XCTAssertTrue(out.contains("https://di.fm/"), "tabs should still list when total is unavailable")
        XCTAssertTrue(out.contains("not separately attributable"),
                      "unattributable browser memory must be stated honestly")
        XCTAssertTrue(out.contains("--responsible-pid"),
                      "the note should point the user at the signal that fixes it")
        XCTAssertFalse(out.contains("[measured]"),
                       "no measured marker when there is no measured total")
    }

    // The per-browser subheader prints the real measured total + process count.
    func testBrowserTabsShowsMeasuredPerBrowserTotal() {
        let snap = MemorySnapshot(
            topApps: [], appsStatus: .ok, unreadableProcessCount: 0,
            swap: nil, compressedUsers: [], swapStatus: .ok,
            browsers: [BrowserMemory(browser: "Brave Browser", totalFootprintBytes: 12_884_901_888,
                                     processCount: 41,
                                     tabs: [BrowserTab(title: "BP", url: "https://beatport.com/")])],
            tabsStatus: .ok)
        let out = TextRenderer.render(snap)
        XCTAssertTrue(out.contains("Brave Browser — 12.0 GB across 41 processes"),
                      "subheader must show the measured total and process count")
        XCTAssertTrue(out.contains("[measured]"), "measured total carries the [measured] marker")
        XCTAssertTrue(out.contains("https://beatport.com/"), "tabs list under the subheader")
    }

    // The tab list is capped at tabsPerBrowser; the remainder is reported honestly,
    // and the subheader still shows the TRUE total tab count.
    func testTabListIsCappedWithHonestRemainder() {
        let tabs = (0..<25).map { BrowserTab(title: "t\($0)", url: "https://e.com/\($0)") }
        let snap = MemorySnapshot(
            topApps: [], appsStatus: .ok, unreadableProcessCount: 0,
            swap: nil, compressedUsers: [], swapStatus: .ok,
            browsers: [BrowserMemory(browser: "Brave Browser", totalFootprintBytes: 1024,
                                     processCount: 3, tabs: tabs)],
            tabsStatus: .ok)
        let out = TextRenderer.render(snap, tabsPerBrowser: 10)
        XCTAssertTrue(out.contains("· 25 tabs"), "subheader shows the true tab count")
        XCTAssertTrue(out.contains("https://e.com/9"), "first 10 tabs are listed")
        XCTAssertFalse(out.contains("https://e.com/10"), "tabs beyond the cap are not listed")
        XCTAssertTrue(out.contains("(+15 more)"), "the remainder is reported, not silently dropped")
    }

    // FINDING 7: partial message for tabs section must not mention "sudo" or unreadable counts
    func testTabsPartialMessageIsContextAppropriate() {
        let snap = MemorySnapshot(
            topApps: [], appsStatus: .ok, unreadableProcessCount: 0,
            swap: nil, compressedUsers: [], swapStatus: .ok,
            browsers: [], tabsStatus: .partial)
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
            browsers: [], tabsStatus: .ok)
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
            browsers: [BrowserMemory(browser: "Brave Browser", totalFootprintBytes: 100, processCount: 1,
                                     tabs: [BrowserTab(title: "Loaded Page", url: "https://loaded.com")])],
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
            browsers: [], tabsStatus: .ok)
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

    func testTopUnavailableRendersAsUnavailableNotNoneMeasured() {
        let snap = MemorySnapshot(
            topApps: [], appsStatus: .ok, unreadableProcessCount: 0,
            swap: SwapInfo(totalBytes: 1_073_741_824, usedBytes: 536_870_912,
                           freeBytes: 536_870_912, swapIns: 0, swapOuts: 0),
            compressedUsers: [], compressedAvailable: false,
            swapStatus: .ok, browsers: [], tabsStatus: .ok)
        let out = TextRenderer.render(snap)
        XCTAssertTrue(out.contains("unavailable (could not read from top)"),
                      "top failure should render as unavailable, not none measured")
        XCTAssertFalse(out.contains("none measured"),
                       "top failure must not render as 'none measured'")
    }

    func testJSONRendererIsValidAndRoundTrips() throws {
        let json = try JSONRenderer.render(fixture())
        let decoded = try JSONDecoder().decode(MemorySnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(decoded, fixture())
    }

    // middleTruncate preserves the head and the trailing token; ellipsis sits in the middle.
    func testMiddleTruncatePreservesHeadAndTail() {
        let s = "make — projectAlpha/services/backend (worker-multi-2)"
        let out = TextRenderer.middleTruncate(s, width: 30)
        XCTAssertEqual(out.count, 30, "truncated label must be exactly the requested width")
        XCTAssertTrue(out.hasPrefix("make"), "process name must survive at the head")
        XCTAssertTrue(out.hasSuffix("2)"), "trailing argv token must survive at the tail")
        XCTAssertTrue(out.contains("…"), "middle truncation uses an ellipsis")
    }

    // A label at or under the width is returned unchanged.
    func testMiddleTruncateNoOpWhenWithinWidth() {
        XCTAssertEqual(TextRenderer.middleTruncate("short", width: 30), "short")
    }

    // Degenerate: name + trailing token alone exceed the cap — name must NOT be dropped.
    func testMiddleTruncateDegenerateKeepsName() {
        let s = "make — " + String(repeating: "x", count: 200) + " (run-api-target)"
        let out = TextRenderer.middleTruncate(s, width: 60)
        XCTAssertEqual(out.count, 60)
        XCTAssertTrue(out.hasPrefix("make"), "process name must never be silently dropped")
        XCTAssertTrue(out.hasSuffix(")"), "trailing token end must survive")
    }

    // TOP APPS auto-sizes the name column to the longest shown label, capped at 60,
    // and middle-truncates only beyond the cap (trailing argv token survives).
    func testTopAppsAutoSizesAndMiddleTruncatesOverCap() {
        let longLabel = "make — " + String(repeating: "deep/", count: 30) + "backend (worker-multi-2)"
        let snap = MemorySnapshot(
            topApps: [
                AppGroup(name: "node — svc/api (index.js)", bundleID: nil,
                         totalFootprintBytes: 100, processCount: 1, pids: [1]),
                AppGroup(name: longLabel, bundleID: nil,
                         totalFootprintBytes: 200, processCount: 2, pids: [2, 3]),
            ],
            appsStatus: .ok, unreadableProcessCount: 0,
            swap: nil, compressedUsers: [], swapStatus: .ok,
            browsers: [], tabsStatus: .ok)
        let out = TextRenderer.render(snap)
        // The shorter, under-cap label renders in full.
        XCTAssertTrue(out.contains("node — svc/api (index.js)"))
        // The over-cap label is middle-truncated but keeps its name and trailing token.
        XCTAssertTrue(out.contains("…"), "over-cap label must be middle-truncated")
        XCTAssertTrue(out.contains("(worker-multi-2)"), "trailing argv token must survive truncation")
        XCTAssertTrue(out.contains("make — "), "process name + dir head must survive truncation")
    }
}
