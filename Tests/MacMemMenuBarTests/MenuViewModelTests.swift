import XCTest
@testable import MacMemMenuBar
@testable import MacMemCore

@MainActor
final class MenuViewModelTests: XCTestCase {
    private func makeProvider(pressure: MemoryPressure = .normal) -> FakeMemoryProvider {
        var p = FakeMemoryProvider(
            processes: [ProcessSample(pid: 1, ppid: 0, responsiblePID: nil, bundleID: "com.x",
                                      name: "X", executablePath: nil, footprintBytes: 100,
                                      residentBytes: 100, pageIns: 0, isReadable: true)],
            swap: SwapInfo(totalBytes: 0, usedBytes: 0, freeBytes: 0, swapIns: 0, swapOuts: 0))
        p.pressureValue = pressure
        return p
    }

    private func group(_ name: String) -> AppGroup {
        AppGroup(name: name, bundleID: "com.x", totalFootprintBytes: 100, processCount: 1, pids: [1])
    }

    func testRefreshPublishesPressureAndSnapshot() async {
        let actions = FakeSystemActions()
        let vm = MenuViewModel(provider: makeProvider(pressure: .critical), tabSource: nil, actions: actions)
        vm.setMenuOpen(true)
        await vm.refreshNow()
        XCTAssertEqual(vm.pressure, .critical)
        XCTAssertNotNil(vm.snapshot)
        XCTAssertEqual(vm.snapshot?.topApps.first?.name, "X")
    }

    func testQuitGoesThroughConfirmationStateMachine() async {
        let actions = FakeSystemActions()
        let vm = MenuViewModel(provider: makeProvider(), tabSource: nil, actions: actions)
        vm.requestQuit(group("Brave Browser"))
        XCTAssertEqual(vm.pendingConfirmation, .quit(group("Brave Browser")))
        XCTAssertEqual(actions.quitCalls.count, 0)
        await vm.confirmPending()
        XCTAssertEqual(actions.quitCalls.map(\.name), ["Brave Browser"])
        XCTAssertNil(vm.pendingConfirmation)
    }

    func testCancelConfirmationDoesNotAct() async {
        let actions = FakeSystemActions()
        let vm = MenuViewModel(provider: makeProvider(), tabSource: nil, actions: actions)
        vm.requestPurge()
        XCTAssertEqual(vm.pendingConfirmation, .purge)
        vm.cancelPending()
        XCTAssertNil(vm.pendingConfirmation)
        await vm.confirmPending()
        XCTAssertEqual(actions.purgeCallCount, 0)
    }

    func testCopyRendersSnapshotThroughActions() async {
        let actions = FakeSystemActions()
        let vm = MenuViewModel(provider: makeProvider(), tabSource: nil, actions: actions)
        vm.setMenuOpen(true)
        await vm.refreshNow()
        vm.copySnapshot()
        XCTAssertNotNil(actions.copiedText)
        XCTAssertTrue(actions.copiedText?.contains("TOP APPS") ?? false,
                      "copied text should be the CLI TextRenderer output")
    }

    func testRevealForwardsToActions() {
        let actions = FakeSystemActions()
        let vm = MenuViewModel(provider: makeProvider(), tabSource: nil, actions: actions)
        vm.reveal(group("A"))
        XCTAssertEqual(actions.revealCalls.map(\.name), ["A"])
    }

    func testFailedActionSurfacesMessage() async {
        let actions = FakeSystemActions()
        actions.purgeResult = .failed("nope")
        let vm = MenuViewModel(provider: makeProvider(), tabSource: nil, actions: actions)
        vm.requestPurge()
        await vm.confirmPending()
        XCTAssertEqual(vm.lastActionMessage, "nope")
    }
}
