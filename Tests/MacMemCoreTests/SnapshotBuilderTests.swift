import XCTest
@testable import MacMemCore

private struct DummyError: Error {}

final class SnapshotBuilderTests: XCTestCase {
    private func sample(_ pid: Int32, name: String, bundle: String?, footprint: UInt64,
                        pageIns: UInt64 = 0, compressed: UInt64? = nil, readable: Bool = true) -> ProcessSample {
        ProcessSample(pid: pid, ppid: 0, responsiblePID: nil, bundleID: bundle, name: name,
                      executablePath: nil, footprintBytes: footprint, residentBytes: footprint,
                      pageIns: pageIns, compressedBytes: compressed, isReadable: readable)
    }

    func testBuildsAllSectionsOK() {
        let provider = FakeMemoryProvider(
            processes: [sample(1, name: "Brave Browser", bundle: "com.brave.Browser", footprint: 100, pageIns: 50)],
            swap: SwapInfo(totalBytes: 100, usedBytes: 40, freeBytes: 60, swapIns: 3, swapOuts: 1))
        let tabSource = FakeTabSource(byBrowser: [
            "Brave Browser": [RawTab(title: "A", url: "https://a.com", windowIndex: 0, tabIndex: 0)]])
        let snap = SnapshotBuilder(provider: provider, tabSource: tabSource).build(topN: 10)

        XCTAssertEqual(snap.appsStatus, .ok)
        XCTAssertEqual(snap.topApps.first?.name, "Brave Browser")
        XCTAssertEqual(snap.swapStatus, .ok)
        XCTAssertEqual(snap.swap?.usedBytes, 40)
        XCTAssertEqual(snap.tabsStatus, .ok)
        XCTAssertEqual(snap.topTabs.first?.url, "https://a.com")
        XCTAssertEqual(snap.unreadableProcessCount, 0)
    }

    func testUnreadableProcessesAreCounted() {
        let provider = FakeMemoryProvider(
            processes: [sample(1, name: "A", bundle: "com.a", footprint: 10),
                        sample(2, name: "root", bundle: nil, footprint: 0, readable: false)],
            swap: SwapInfo(totalBytes: 0, usedBytes: 0, freeBytes: 0, swapIns: 0, swapOuts: 0))
        let snap = SnapshotBuilder(provider: provider, tabSource: nil).build()
        XCTAssertEqual(snap.unreadableProcessCount, 1)
    }

    func testProviderFailureYieldsErrorStatusNotCrash() {
        let provider = FakeMemoryProvider(
            processes: [], swap: SwapInfo(totalBytes: 0, usedBytes: 0, freeBytes: 0, swapIns: 0, swapOuts: 0),
            processError: DummyError())
        let snap = SnapshotBuilder(provider: provider, tabSource: nil).build()
        XCTAssertEqual(snap.appsStatus, .error)
        XCTAssertTrue(snap.topApps.isEmpty)
    }

    func testTabSourceFailureYieldsPartialTabs() {
        let provider = FakeMemoryProvider(
            processes: [sample(1, name: "A", bundle: "com.a", footprint: 10)],
            swap: SwapInfo(totalBytes: 0, usedBytes: 0, freeBytes: 0, swapIns: 0, swapOuts: 0))
        let tabSource = FakeTabSource(byBrowser: ["Brave Browser": []],
                                      errorsByBrowser: ["Brave Browser": DummyError()])
        let snap = SnapshotBuilder(provider: provider, tabSource: tabSource).build()
        XCTAssertEqual(snap.tabsStatus, .partial)
    }

    func testNilTabSourceMarksTabsPermissionNeeded() {
        let provider = FakeMemoryProvider(
            processes: [], swap: SwapInfo(totalBytes: 0, usedBytes: 0, freeBytes: 0, swapIns: 0, swapOuts: 0))
        let snap = SnapshotBuilder(provider: provider, tabSource: nil).build()
        XCTAssertEqual(snap.tabsStatus, .permissionNeeded)
    }

    // FINDING 1: renderer-only filtering — a realistic group (main + GPU + 3 renderers)
    // must produce estimates when tab count == renderer count; a group whose renderers
    // differ from the tab count must still blank.
    func testRendererFootprintsFiltersToRendererProcessesOnly() {
        // Brave group: 1 main process + 1 GPU helper + 3 renderer helpers = 5 pids total
        let braveMain    = sample(10, name: "Brave Browser",
                                  bundle: "com.brave.Browser",               footprint: 500)
        let braveGPU     = sample(11, name: "Brave Browser Helper (GPU)",
                                  bundle: "com.brave.Browser.helper.gpu",    footprint: 200)
        let braveR1      = sample(12, name: "Brave Browser Helper (Renderer)",
                                  bundle: "com.brave.Browser.helper.renderer", footprint: 300)
        let braveR2      = sample(13, name: "Brave Browser Helper (Renderer)",
                                  bundle: "com.brave.Browser.helper.renderer", footprint: 250)
        let braveR3      = sample(14, name: "Brave Browser Helper (Renderer)",
                                  bundle: "com.brave.Browser.helper.renderer", footprint: 180)

        let provider = FakeMemoryProvider(
            processes: [braveMain, braveGPU, braveR1, braveR2, braveR3],
            swap: SwapInfo(totalBytes: 0, usedBytes: 0, freeBytes: 0, swapIns: 0, swapOuts: 0))

        // 3 tabs → should match 3 renderer footprints after filtering
        let tabSource = FakeTabSource(byBrowser: ["Brave Browser": [
            RawTab(title: "T1", url: "https://t1.com", windowIndex: 0, tabIndex: 0),
            RawTab(title: "T2", url: "https://t2.com", windowIndex: 0, tabIndex: 1),
            RawTab(title: "T3", url: "https://t3.com", windowIndex: 0, tabIndex: 2),
        ]])

        let snap = SnapshotBuilder(provider: provider, tabSource: tabSource).build(topN: 10)

        // All three tabs should have estimates (count-match succeeded after renderer filter)
        XCTAssertEqual(snap.topTabs.count, 3, "expected 3 tabs")
        XCTAssertTrue(snap.topTabs.allSatisfy { $0.estimatedBytes != nil },
                      "all tabs should have estimates when renderer count == tab count")
    }

    func testRendererFootprintsMismatchStillBlanksEstimates() {
        // 2 renderer processes but 3 tabs → mismatch, estimates must be nil
        let braveMain    = sample(20, name: "Brave Browser",
                                  bundle: "com.brave.Browser",               footprint: 500)
        let braveGPU     = sample(21, name: "Brave Browser Helper (GPU)",
                                  bundle: "com.brave.Browser.helper.gpu",    footprint: 200)
        let braveR1      = sample(22, name: "Brave Browser Helper (Renderer)",
                                  bundle: "com.brave.Browser.helper.renderer", footprint: 300)
        let braveR2      = sample(23, name: "Brave Browser Helper (Renderer)",
                                  bundle: "com.brave.Browser.helper.renderer", footprint: 250)

        let provider = FakeMemoryProvider(
            processes: [braveMain, braveGPU, braveR1, braveR2],
            swap: SwapInfo(totalBytes: 0, usedBytes: 0, freeBytes: 0, swapIns: 0, swapOuts: 0))

        let tabSource = FakeTabSource(byBrowser: ["Brave Browser": [
            RawTab(title: "T1", url: "https://t1.com", windowIndex: 0, tabIndex: 0),
            RawTab(title: "T2", url: "https://t2.com", windowIndex: 0, tabIndex: 1),
            RawTab(title: "T3", url: "https://t3.com", windowIndex: 0, tabIndex: 2),
        ]])

        let snap = SnapshotBuilder(provider: provider, tabSource: tabSource).build(topN: 10)

        XCTAssertTrue(snap.topTabs.allSatisfy { $0.estimatedBytes == nil },
                      "estimates must be nil when renderer count != tab count")
    }
}
