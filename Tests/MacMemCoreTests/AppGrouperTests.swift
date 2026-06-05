import XCTest
@testable import MacMemCore

final class AppGrouperTests: XCTestCase {
    private func sample(_ pid: Int32, name: String, bundle: String?, footprint: UInt64,
                        responsible: Int32? = nil) -> ProcessSample {
        ProcessSample(pid: pid, ppid: 0, responsiblePID: responsible, bundleID: bundle,
                      name: name, executablePath: nil, footprintBytes: footprint,
                      residentBytes: footprint, pageIns: 0, isReadable: true)
    }

    func testHelpersCollapseViaBundleSuffixStripping() {
        let samples = [
            sample(1, name: "Brave Browser", bundle: "com.brave.Browser", footprint: 100),
            sample(2, name: "Brave Browser Helper (Renderer)", bundle: "com.brave.Browser.helper.renderer", footprint: 300),
            sample(3, name: "Brave Browser Helper (GPU)", bundle: "com.brave.Browser.helper.gpu", footprint: 50),
        ]
        let groups = AppGrouper().group(samples, topN: 10)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].name, "Brave Browser")
        XCTAssertEqual(groups[0].bundleID, "com.brave.Browser")
        XCTAssertEqual(groups[0].totalFootprintBytes, 450)
        XCTAssertEqual(groups[0].processCount, 3)
        XCTAssertEqual(groups[0].pids, [1, 2, 3])
    }

    func testResponsiblePIDOverridesGrouping() {
        let samples = [
            sample(10, name: "Code", bundle: "com.microsoft.VSCode", footprint: 200),
            sample(11, name: "Code Helper", bundle: nil, footprint: 400, responsible: 10),
        ]
        let groups = AppGrouper().group(samples, topN: 10)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].name, "Code")
        XCTAssertEqual(groups[0].totalFootprintBytes, 600)
    }

    func testTopNAndDescendingOrder() {
        let samples = (1...15).map { sample(Int32($0), name: "App\($0)", bundle: "com.x.app\($0)", footprint: UInt64($0)) }
        let groups = AppGrouper().group(samples, topN: 10)
        XCTAssertEqual(groups.count, 10)
        XCTAssertEqual(groups.first?.name, "App15")
        XCTAssertEqual(groups.last?.name, "App6")
    }

    func testResponsiblePIDCycleDoesNotInfiniteLoop() {
        let samples = [
            sample(1, name: "A", bundle: "com.a", footprint: 10, responsible: 2),
            sample(2, name: "B", bundle: "com.b", footprint: 10, responsible: 1),
        ]
        let groups = AppGrouper().group(samples, topN: 10)
        let inputTotal = samples.reduce(0) { $0 + Int($1.footprintBytes) }
        let groupedTotal = groups.reduce(0) { $0 + Int($1.totalFootprintBytes) }
        XCTAssertEqual(groupedTotal, inputTotal)   // no process dropped or double-counted
        XCTAssertEqual(groupedTotal, 20)
    }
}
