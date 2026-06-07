import XCTest
@testable import MacMemCore

final class CompressedMemoryAggregatorTests: XCTestCase {
    private func group(_ name: String, pids: [Int32]) -> AppGroup {
        AppGroup(name: name, bundleID: nil, totalFootprintBytes: 0, processCount: pids.count, pids: pids)
    }

    func testRanksByAggregatedMeasuredCompressed() {
        let groups = [group("Heavy", pids: [1, 2]), group("Light", pids: [3])]
        let result = CompressedMemoryAggregator().entries(
            groups: groups,
            compressedByPID: [1: 600, 2: 200, 3: 200])
        XCTAssertEqual(result.map(\.appName), ["Heavy", "Light"])
        // Measured sum, NOT a proportional share of total swap.
        XCTAssertEqual(result[0].compressedBytes, 800)
        XCTAssertEqual(result[1].compressedBytes, 200)
    }

    func testPIDsMissingFromMapContributeZero() {
        let groups = [group("A", pids: [1, 2])]
        // pid 2 not in map — contributes 0
        let result = CompressedMemoryAggregator().entries(
            groups: groups,
            compressedByPID: [1: 500])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].compressedBytes, 500)
    }

    func testGroupsWithZeroCompressedAreExcluded() {
        let result = CompressedMemoryAggregator().entries(
            groups: [group("Z", pids: [1])],
            compressedByPID: [1: 0])
        XCTAssertTrue(result.isEmpty)

        // pid not in map at all → total 0 → excluded
        let resultMissing = CompressedMemoryAggregator().entries(
            groups: [group("Z", pids: [1])],
            compressedByPID: [:])
        XCTAssertTrue(resultMissing.isEmpty)
    }

    func testNegativeTopNReturnsEmpty() {
        let result = CompressedMemoryAggregator().entries(
            groups: [group("Heavy", pids: [1])],
            compressedByPID: [1: 600],
            topN: -1)
        XCTAssertEqual(result.count, 0)
    }
}
