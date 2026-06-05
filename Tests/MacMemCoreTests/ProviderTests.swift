import XCTest
@testable import MacMemCore

final class ProviderTests: XCTestCase {
    func testFakeProviderReturnsInjectedData() throws {
        let sample = ProcessSample(pid: 1, ppid: 0, responsiblePID: nil, bundleID: nil,
                                   name: "x", executablePath: nil, footprintBytes: 10,
                                   residentBytes: 5, pageIns: 0, isReadable: true)
        let swap = SwapInfo(totalBytes: 1, usedBytes: 0, freeBytes: 1, swapIns: 0, swapOuts: 0)
        let provider = FakeMemoryProvider(processes: [sample], swap: swap)
        XCTAssertEqual(try provider.listProcesses(), [sample])
        XCTAssertEqual(try provider.readSwap(), swap)
    }
}
