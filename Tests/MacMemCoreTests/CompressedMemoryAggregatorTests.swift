import XCTest
@testable import MacMemCore

final class CompressedMemoryAggregatorTests: XCTestCase {
    private func group(_ name: String, pids: [Int32]) -> AppGroup {
        AppGroup(name: name, bundleID: nil, totalFootprintBytes: 0, processCount: pids.count, pids: pids)
    }
    private func sample(_ pid: Int32, compressed: UInt64?) -> ProcessSample {
        ProcessSample(pid: pid, ppid: 0, responsiblePID: nil, bundleID: nil, name: "p\(pid)",
                      executablePath: nil, footprintBytes: 0, residentBytes: 0,
                      pageIns: 0, compressedBytes: compressed, isReadable: true)
    }

    func testRanksByAggregatedMeasuredCompressed() {
        let groups = [group("Heavy", pids: [1, 2]), group("Light", pids: [3])]
        let samples = [sample(1, compressed: 600), sample(2, compressed: 200), sample(3, compressed: 200)]
        let result = CompressedMemoryAggregator().entries(groups: groups, samples: samples)
        XCTAssertEqual(result.map(\.appName), ["Heavy", "Light"])
        // Measured sum, NOT a proportional share of total swap.
        XCTAssertEqual(result[0].compressedBytes, 800)
        XCTAssertEqual(result[1].compressedBytes, 200)
    }

    func testUnmeasuredProcessesContributeNothing() {
        let groups = [group("A", pids: [1, 2])]
        let samples = [sample(1, compressed: 500), sample(2, compressed: nil)]
        let result = CompressedMemoryAggregator().entries(groups: groups, samples: samples)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].compressedBytes, 500)
    }

    func testGroupsWithZeroCompressedAreExcluded() {
        let result = CompressedMemoryAggregator().entries(
            groups: [group("Z", pids: [1])], samples: [sample(1, compressed: 0)])
        XCTAssertTrue(result.isEmpty)
        let resultNil = CompressedMemoryAggregator().entries(
            groups: [group("Z", pids: [1])], samples: [sample(1, compressed: nil)])
        XCTAssertTrue(resultNil.isEmpty)
    }

    func testNegativeTopNReturnsEmpty() {
        let result = CompressedMemoryAggregator().entries(
            groups: [group("Heavy", pids: [1])], samples: [sample(1, compressed: 600)], topN: -1)
        XCTAssertEqual(result.count, 0)
    }
}
