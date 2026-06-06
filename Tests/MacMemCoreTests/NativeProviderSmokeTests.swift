import XCTest
@testable import MacMemCore

final class NativeProviderSmokeTests: XCTestCase {
    func testListsProcessesIncludingSelfWithFootprint() throws {
        let provider = NativeMemoryProvider()
        let processes = try provider.listProcesses()
        XCTAssertFalse(processes.isEmpty)

        let me = ProcessInfo.processInfo.processIdentifier
        guard let mine = processes.first(where: { $0.pid == me }) else {
            return XCTFail("current process not found in list")
        }
        XCTAssertTrue(mine.isReadable)
        XCTAssertGreaterThan(mine.footprintBytes, 0)
        XCTAssertFalse(mine.name.isEmpty)
    }

    func testReadsSwapTotals() throws {
        let swap = try NativeMemoryProvider().readSwap()
        // total >= used; counters are non-negative by type. Just assert it returns.
        XCTAssertGreaterThanOrEqual(swap.totalBytes, swap.usedBytes)
    }
}
