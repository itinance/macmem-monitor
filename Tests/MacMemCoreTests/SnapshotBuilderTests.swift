import XCTest
@testable import MacMemCore

private struct DummyError: Error {}

final class SnapshotBuilderTests: XCTestCase {
    private func sample(_ pid: Int32, name: String, bundle: String?, footprint: UInt64,
                        pageIns: UInt64 = 0, readable: Bool = true) -> ProcessSample {
        ProcessSample(pid: pid, ppid: 0, responsiblePID: nil, bundleID: bundle, name: name,
                      executablePath: nil, footprintBytes: footprint, residentBytes: footprint,
                      pageIns: pageIns, isReadable: readable)
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
}
