import XCTest
@testable import MacMemMenuBar
@testable import MacMemCore

/// Counts which provider methods get called so we can assert the engine's mode behavior.
// @unchecked Sendable: the counters are mutated from the detached snapshot task and
// read on the main actor only AFTER `await tick()` returns. The await establishes a
// happens-before edge (tick awaits the detached task's `.value`), so there is no race.
private final class SpyProvider: MemoryProvider, @unchecked Sendable {
    private(set) var pressureCalls = 0
    private(set) var listCalls = 0
    var pressureValue: MemoryPressure = .warn

    func listProcesses() throws -> [ProcessSample] { listCalls += 1; return [] }
    func readSwap() throws -> SwapInfo {
        SwapInfo(totalBytes: 0, usedBytes: 0, freeBytes: 0, swapIns: 0, swapOuts: 0)
    }
    func compressedByPID() throws -> [pid_t: UInt64] { [:] }
    func pressure() -> MemoryPressure { pressureCalls += 1; return pressureValue }
}

@MainActor
final class SnapshotEngineTests: XCTestCase {
    func testCollapsedTickReadsOnlyPressure() async {
        let spy = SpyProvider()
        var gotPressure: MemoryPressure?
        var gotSnapshot = false
        let engine = SnapshotEngine(provider: spy, tabSource: nil, topN: 10)
        engine.onPressure = { gotPressure = $0 }
        engine.onSnapshot = { _ in gotSnapshot = true }

        // Use setMode (test-only, no auto-tick) to avoid a race with a
        // fire-and-forget Task that could add extra pressureCalls before
        // the assertions below.
        engine.setMode(.collapsed)
        await engine.tick()

        XCTAssertEqual(gotPressure, .warn)
        XCTAssertEqual(spy.pressureCalls, 1)
        XCTAssertEqual(spy.listCalls, 0, "collapsed mode must not build a full snapshot")
        XCTAssertFalse(gotSnapshot)
    }

    func testOpenTickBuildsFullSnapshotAndPressure() async {
        let spy = SpyProvider()
        var gotSnapshot: MemorySnapshot?
        let engine = SnapshotEngine(provider: spy, tabSource: nil, topN: 10)
        engine.onSnapshot = { gotSnapshot = $0 }

        // Use setMode to avoid extra ticks from setMenuOpen's auto-tick Task.
        engine.setMode(.open)
        await engine.tick()

        XCTAssertEqual(spy.pressureCalls, 1, "open mode still updates pressure")
        XCTAssertEqual(spy.listCalls, 1, "open mode builds a full snapshot")
        XCTAssertNotNil(gotSnapshot)
    }

    func testIntervalSwitchesWithMode() {
        let spy = SpyProvider()
        let engine = SnapshotEngine(provider: spy, tabSource: nil, topN: 10)
        engine.setMode(.collapsed)
        XCTAssertEqual(engine.currentInterval, 5.0, accuracy: 0.001)
        engine.setMode(.open)
        XCTAssertEqual(engine.currentInterval, 2.5, accuracy: 0.001)
    }
}
