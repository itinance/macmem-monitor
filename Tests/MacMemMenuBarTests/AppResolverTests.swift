import XCTest
@testable import MacMemMenuBar
@testable import MacMemCore

final class AppResolverTests: XCTestCase {
    private func group(name: String, bundle: String?, pids: [Int32]) -> AppGroup {
        AppGroup(name: name, bundleID: bundle, totalFootprintBytes: 1, processCount: pids.count, pids: pids)
    }

    func testMatchesByBundleIDFirst() {
        let candidates: [AppCandidate] = [
            AppCandidate(bundleID: "com.brave.Browser", pid: 10),
            AppCandidate(bundleID: "com.other", pid: 11),
        ]
        let g = group(name: "Brave Browser", bundle: "com.brave.Browser", pids: [99])
        XCTAssertEqual(AppResolver.matchIndex(group: g, candidates: candidates), 0)
    }

    func testFallsBackToPIDWhenNoBundleMatch() {
        let candidates: [AppCandidate] = [
            AppCandidate(bundleID: nil, pid: 42),
            AppCandidate(bundleID: "com.other", pid: 11),
        ]
        let g = group(name: "node", bundle: nil, pids: [42])
        XCTAssertEqual(AppResolver.matchIndex(group: g, candidates: candidates), 0)
    }

    func testReturnsNilWhenNoMatch() {
        let candidates: [AppCandidate] = [AppCandidate(bundleID: "com.other", pid: 11)]
        let g = group(name: "Ghost", bundle: "com.ghost", pids: [7])
        XCTAssertNil(AppResolver.matchIndex(group: g, candidates: candidates))
    }
}
