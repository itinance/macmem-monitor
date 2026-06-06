import XCTest
@testable import MacMemCore

final class SwapEstimatorTests: XCTestCase {
    private func group(_ name: String, pids: [Int32]) -> AppGroup {
        AppGroup(name: name, bundleID: nil, totalFootprintBytes: 0, processCount: pids.count, pids: pids)
    }
    private func sample(_ pid: Int32, pageIns: UInt64) -> ProcessSample {
        ProcessSample(pid: pid, ppid: 0, responsiblePID: nil, bundleID: nil, name: "p\(pid)",
                      executablePath: nil, footprintBytes: 0, residentBytes: 0,
                      pageIns: pageIns, isReadable: true)
    }

    func testNoCulpritsWhenSwapUnused() {
        let swap = SwapInfo(totalBytes: 100, usedBytes: 0, freeBytes: 100, swapIns: 0, swapOuts: 0)
        let result = SwapEstimator().culprits(groups: [group("A", pids: [1])],
                                              samples: [sample(1, pageIns: 999)], swap: swap)
        XCTAssertTrue(result.isEmpty)
    }

    func testRanksByAggregatedPageInsWithConfidence() {
        let swap = SwapInfo(totalBytes: 100, usedBytes: 80, freeBytes: 20, swapIns: 10, swapOuts: 5)
        let groups = [group("Heavy", pids: [1, 2]), group("Light", pids: [3])]
        let samples = [sample(1, pageIns: 600), sample(2, pageIns: 200), sample(3, pageIns: 200)]
        let result = SwapEstimator().culprits(groups: groups, samples: samples, swap: swap)
        XCTAssertEqual(result.map(\.appName), ["Heavy", "Light"])
        XCTAssertEqual(result[0].score, 800)
        XCTAssertEqual(result[0].confidence, .high)   // 800/1000 = 0.8 > 0.5
        XCTAssertEqual(result[1].confidence, .low)    // 200/1000 = 0.2, not > 0.2
        // Estimated swap = proportional share of usedBytes (80) by page-in share.
        XCTAssertEqual(result[0].estimatedSwapBytes, 64)  // 0.8 * 80
        XCTAssertEqual(result[1].estimatedSwapBytes, 16)  // 0.2 * 80
        // Attributions sum to (approximately) the used-swap total.
        XCTAssertEqual(result.reduce(0) { $0 + $1.estimatedSwapBytes }, swap.usedBytes)
    }

    // Fix 2 (Critical): negative topN must not trap — must return empty array.
    func testNegativeTopNReturnsEmpty() {
        let swap = SwapInfo(totalBytes: 100, usedBytes: 80, freeBytes: 20, swapIns: 10, swapOuts: 5)
        let groups = [group("Heavy", pids: [1])]
        let samples = [sample(1, pageIns: 600)]
        // Must not crash and must return []
        let result = SwapEstimator().culprits(groups: groups, samples: samples, swap: swap, topN: -1)
        XCTAssertEqual(result.count, 0)
    }

    func testGroupsWithZeroPageInsAreExcluded() {
        let swap = SwapInfo(totalBytes: 100, usedBytes: 50, freeBytes: 50, swapIns: 1, swapOuts: 1)
        let result = SwapEstimator().culprits(groups: [group("Z", pids: [1])],
                                              samples: [sample(1, pageIns: 0)], swap: swap)
        XCTAssertTrue(result.isEmpty)
    }
}
