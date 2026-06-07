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

    func testReadsWorkingDirectoryForOwnProcess() throws {
        let provider = NativeMemoryProvider()
        let processes = try provider.listProcesses()
        let me = ProcessInfo.processInfo.processIdentifier
        guard let mine = processes.first(where: { $0.pid == me }) else {
            return XCTFail("current process not found in list")
        }
        // The test process's own cwd is readable without sudo.
        let cwd = try XCTUnwrap(mine.workingDirectory, "own process cwd should be readable")
        XCTAssertTrue(cwd.hasPrefix("/"), "cwd should be an absolute path")
        // commandLine is best-effort: if present it must be non-empty (no crash either way).
        if let cmd = mine.commandLine {
            XCTAssertFalse(cmd.isEmpty)
        }
    }
}
