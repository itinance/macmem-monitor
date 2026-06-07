import XCTest
@testable import MacMemCore

private struct DummyError: Error {}

final class SnapshotBuilderTests: XCTestCase {
    private func sample(_ pid: Int32, name: String, bundle: String?, footprint: UInt64,
                        pageIns: UInt64 = 0, readable: Bool = true,
                        cwd: String? = nil, cmd: String? = nil) -> ProcessSample {
        ProcessSample(pid: pid, ppid: 0, responsiblePID: nil, bundleID: bundle, name: name,
                      executablePath: nil, footprintBytes: footprint, residentBytes: footprint,
                      pageIns: pageIns, isReadable: readable,
                      workingDirectory: cwd, commandLine: cmd)
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
        XCTAssertEqual(snap.browsers.first?.browser, "Brave Browser")
        XCTAssertEqual(snap.browsers.first?.tabs.first?.url, "https://a.com")
        // The browser's MEASURED total = sum of its processes' footprints (here a single 100-byte process).
        XCTAssertEqual(snap.browsers.first?.totalFootprintBytes, 100)
        XCTAssertEqual(snap.browsers.first?.processCount, 1)
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

    func testNoSwapSkipsCompressedPathAndLeavesAvailableTrue() {
        let provider = FakeMemoryProvider(
            processes: [sample(1, name: "App", bundle: "com.x", footprint: 100)],
            swap: SwapInfo(totalBytes: 0, usedBytes: 0, freeBytes: 0, swapIns: 0, swapOuts: 0),
            compressed: [1: 500_000])
        let snap = SnapshotBuilder(provider: provider, tabSource: nil).build(includeSwap: false)
        XCTAssertEqual(snap.compressedUsers, [], "no-swap build must yield empty compressedUsers")
        XCTAssertTrue(snap.compressedAvailable, "compressedAvailable should be neutral true when swap section is skipped")
    }

    func testCompressedMapProducesGroupedAndRankedCompressedUsers() {
        // Two apps: Heavy (pids 1+2) and Light (pid 3)
        let provider = FakeMemoryProvider(
            processes: [
                sample(1, name: "Heavy App", bundle: "com.heavy", footprint: 100),
                sample(2, name: "Heavy App Helper", bundle: "com.heavy.helper", footprint: 50),
                sample(3, name: "Light App", bundle: "com.light", footprint: 20),
            ],
            swap: SwapInfo(totalBytes: 200, usedBytes: 100, freeBytes: 100, swapIns: 0, swapOuts: 0),
            // pid 1 → 600, pid 2 → 200, pid 3 → 200; Heavy total = 800, Light = 200
            compressed: [1: 600, 2: 200, 3: 200])
        let snap = SnapshotBuilder(provider: provider, tabSource: nil).build(topN: 10)
        // Heavy App and its helper share bundle prefix "com.heavy" → grouped under Heavy App
        let names = snap.compressedUsers.map(\.appName)
        XCTAssertTrue(names.contains("Heavy App"), "Heavy App should appear in compressedUsers")
        // Heavy App should have more compressed bytes than Light App
        if let heavy = snap.compressedUsers.first(where: { $0.appName == "Heavy App" }),
           let light = snap.compressedUsers.first(where: { $0.appName == "Light App" }) {
            XCTAssertGreaterThan(heavy.compressedBytes, light.compressedBytes,
                                 "Heavy App should rank above Light App by compressed bytes")
        }
    }

    // The per-browser total is the MEASURED sum of ALL the browser's processes
    // (main + GPU + renderers fold into one bundle-id group), not a renderer subset.
    func testBrowserTotalSumsAllBrowserProcesses() {
        // Brave group: 1 main + 1 GPU + 3 renderer helpers, all folding under com.brave.Browser.
        let braveMain    = sample(10, name: "Brave Browser",
                                  bundle: "com.brave.Browser",                footprint: 500)
        let braveGPU     = sample(11, name: "Brave Browser Helper (GPU)",
                                  bundle: "com.brave.Browser.helper.gpu",     footprint: 200)
        let braveR1      = sample(12, name: "Brave Browser Helper (Renderer)",
                                  bundle: "com.brave.Browser.helper.renderer", footprint: 300)
        let braveR2      = sample(13, name: "Brave Browser Helper (Renderer)",
                                  bundle: "com.brave.Browser.helper.renderer", footprint: 250)
        let braveR3      = sample(14, name: "Brave Browser Helper (Renderer)",
                                  bundle: "com.brave.Browser.helper.renderer", footprint: 180)

        let provider = FakeMemoryProvider(
            processes: [braveMain, braveGPU, braveR1, braveR2, braveR3],
            swap: SwapInfo(totalBytes: 0, usedBytes: 0, freeBytes: 0, swapIns: 0, swapOuts: 0))

        let tabSource = FakeTabSource(byBrowser: ["Brave Browser": [
            RawTab(title: "T1", url: "https://t1.com", windowIndex: 0, tabIndex: 0),
            RawTab(title: "T2", url: "https://t2.com", windowIndex: 0, tabIndex: 1),
        ]])

        let snap = SnapshotBuilder(provider: provider, tabSource: tabSource).build(topN: 10)

        let brave = snap.browsers.first { $0.browser == "Brave Browser" }
        XCTAssertEqual(brave?.tabs.count, 2, "every open tab is listed")
        XCTAssertEqual(brave?.totalFootprintBytes, 1430, "total = 500+200+300+250+180 across all processes")
        XCTAssertEqual(brave?.processCount, 5, "all five browser processes are counted")
    }

    // Safari's WebKit content lives in the shared system framework and is NOT folded
    // into the Safari group without --responsible-pid, so its total is honestly nil.
    func testSafariContentNotAttributableYieldsNilTotal() {
        let safariMain = sample(30, name: "Safari", bundle: "com.apple.Safari", footprint: 200)
        let webContent = sample(31, name: "Safari Service Worker (di.fm)",
                                bundle: "com.apple.WebKit.WebContent", footprint: 3_000)
        let provider = FakeMemoryProvider(
            processes: [safariMain, webContent],
            swap: SwapInfo(totalBytes: 0, usedBytes: 0, freeBytes: 0, swapIns: 0, swapOuts: 0))
        let tabSource = FakeTabSource(byBrowser: ["Safari": [
            RawTab(title: "DI", url: "https://di.fm/", windowIndex: 0, tabIndex: 0)]])

        let snap = SnapshotBuilder(provider: provider, tabSource: tabSource).build(topN: 10)

        let safari = snap.browsers.first { $0.browser == "Safari" }
        XCTAssertEqual(safari?.tabs.first?.url, "https://di.fm/")
        XCTAssertNil(safari?.totalFootprintBytes,
                     "Safari total must be nil when WebKit content is not folded into it")
    }

    func testPathStyleThreadsThroughToLabels() {
        let provider = FakeMemoryProvider(
            processes: [sample(1, name: "node", bundle: nil, footprint: 100,
                               cwd: "/Users/me/svc/api", cmd: "index.js")],
            swap: SwapInfo(totalBytes: 0, usedBytes: 0, freeBytes: 0, swapIns: 0, swapOuts: 0))
        // Default style is shortestUnique: a singleton cohort shows its last component.
        let def = SnapshotBuilder(provider: provider, tabSource: nil).build(includeSwap: false)
        XCTAssertEqual(def.topApps.first?.name, "node — api (index.js)")
        // .fullPath shows the full path (here unabbreviated — home differs from the test path).
        let full = SnapshotBuilder(provider: provider, tabSource: nil)
            .build(includeSwap: false, pathStyle: .fullPath)
        XCTAssertEqual(full.topApps.first?.name, "node — /Users/me/svc/api (index.js)")
    }
}
