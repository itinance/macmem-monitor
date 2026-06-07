import XCTest
@testable import MacMemCore

final class AppGrouperTests: XCTestCase {
    private func sample(_ pid: Int32, name: String, bundle: String?, footprint: UInt64,
                        responsible: Int32? = nil, ppid: Int32 = 0,
                        cwd: String? = nil, cmd: String? = nil) -> ProcessSample {
        ProcessSample(pid: pid, ppid: ppid, responsiblePID: responsible, bundleID: bundle,
                      name: name, executablePath: nil, footprintBytes: footprint,
                      residentBytes: footprint, pageIns: 0, isReadable: true,
                      workingDirectory: cwd, commandLine: cmd)
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

    // PPID fallback: bundle-less child whose parent has a bundle ID is folded in.
    func testBundlelessChildFoldsIntoParentViaPPID() {
        let samples = [
            sample(100, name: "Ghostty", bundle: "com.mitchellh.ghostty", footprint: 200, ppid: 1),
            sample(101, name: "pidinfo",  bundle: nil,                     footprint:  50, ppid: 100),
        ]
        let groups = AppGrouper().group(samples, topN: 10)
        XCTAssertEqual(groups.count, 1, "child should be folded into parent")
        XCTAssertEqual(groups[0].name, "Ghostty")
        XCTAssertEqual(groups[0].bundleID, "com.mitchellh.ghostty")
        XCTAssertEqual(groups[0].totalFootprintBytes, 250)
        XCTAssertEqual(groups[0].processCount, 2)
    }

    // PPID fallback: bundle-less process with ppid == 1 (launchd) stays its own group.
    func testBundlelessProcessWithLaunchdParentStaysOwnGroup() {
        let samples = [
            sample(200, name: "somecli", bundle: nil, footprint: 80, ppid: 1),
        ]
        let groups = AppGrouper().group(samples, topN: 10)
        XCTAssertEqual(groups.count, 1)
        XCTAssertTrue(groups[0].name.hasPrefix("somecli"), "bare name preserved in collapsed label")
        XCTAssertNil(groups[0].bundleID)
    }

    // PPID fallback: bundle-less process whose parent is NOT in the sample stays its own group.
    func testBundlelessProcessWithMissingParentStaysOwnGroup() {
        // ppid 999 is not in the samples array
        let samples = [
            sample(300, name: "helper", bundle: nil, footprint: 60, ppid: 999),
        ]
        let groups = AppGrouper().group(samples, topN: 10)
        XCTAssertEqual(groups.count, 1)
        XCTAssertTrue(groups[0].name.hasPrefix("helper"), "bare name preserved in collapsed label")
        XCTAssertNil(groups[0].bundleID)
    }

    // A process WITH its own bundle ID must NOT be merged into a parent that has a different bundle ID.
    func testProcessWithBundleIDKeepsOwnIdentity() {
        let samples = [
            sample(400, name: "ParentApp", bundle: "com.parent.App",  footprint: 300, ppid: 1),
            sample(401, name: "ChildApp",  bundle: "com.child.App",   footprint: 100, ppid: 400),
        ]
        let groups = AppGrouper().group(samples, topN: 10)
        XCTAssertEqual(groups.count, 2, "each app with its own bundleID must remain separate")
        let names = groups.map { $0.name }.sorted()
        XCTAssertEqual(names, ["ChildApp", "ParentApp"])
    }

    // PPID cycle (A.ppid=B, B.ppid=A, both bundle-less) must terminate without infinite loop.
    // With the app-parent constraint neither folds (parent is bundle-less), so two separate groups.
    func testPPIDCycleDoesNotInfiniteLoop() {
        let samples = [
            sample(500, name: "cycleA", bundle: nil, footprint: 10, ppid: 501),
            sample(501, name: "cycleB", bundle: nil, footprint: 10, ppid: 500),
        ]
        let groups = AppGrouper().group(samples, topN: 10)
        let inputTotal  = samples.reduce(0) { $0 + Int($1.footprintBytes) }
        let groupedTotal = groups.reduce(0) { $0 + Int($1.totalFootprintBytes) }
        XCTAssertEqual(groupedTotal, inputTotal, "no process dropped or double-counted in PPID cycle")
        XCTAssertEqual(groups.count, 2, "both bundle-less cycle members stay as separate groups")
        let names = groups.map { $0.name }.sorted()
        XCTAssertTrue(names[0].hasPrefix("cycleA"))
        XCTAssertTrue(names[1].hasPrefix("cycleB"))
    }

    // Fix 1 (Critical): negative topN must not trap — must return empty array.
    func testNegativeTopNReturnsEmpty() {
        let samples = [
            sample(1, name: "App", bundle: "com.x.app", footprint: 100),
        ]
        // Must not crash and must return []
        let groups = AppGrouper().group(samples, topN: -1)
        XCTAssertEqual(groups.count, 0)
    }

    // 3-hop chain: child (no bundle) → shell (no bundle) → app (bundle).
    // The shell's immediate parent IS an app → shell folds into app.
    // The child's immediate parent is bundle-less (shell) → child does NOT fold; stays separate.
    func testBundlelessChildOfShellDoesNotFoldThroughShellIntoApp() {
        let samples = [
            sample(600, name: "Ghostty",     bundle: "com.mitchellh.ghostty", footprint: 200, ppid: 1),
            sample(601, name: "zsh",         bundle: nil,                     footprint:  30, ppid: 600),
            sample(602, name: "swift-build", bundle: nil,                     footprint: 150, ppid: 601),
        ]
        let groups = AppGrouper().group(samples, topN: 10)
        // zsh's parent (Ghostty) has a bundle ID → zsh folds into Ghostty.
        // swift-build's parent (zsh) has NO bundle ID → swift-build stays its own group.
        XCTAssertEqual(groups.count, 2, "swift-build must not be buried under Ghostty")
        let byName = Dictionary(groups.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        let ghosttyGroup = byName["Ghostty"]
        XCTAssertNotNil(ghosttyGroup)
        XCTAssertEqual(ghosttyGroup?.totalFootprintBytes, 230, "Ghostty + zsh = 230")
        XCTAssertEqual(ghosttyGroup?.processCount, 2)
        let swiftGroup = groups.first { $0.name.hasPrefix("swift-build") }
        XCTAssertNotNil(swiftGroup)
        XCTAssertEqual(swiftGroup?.totalFootprintBytes, 150)
        XCTAssertEqual(swiftGroup?.processCount, 1)
    }

    // Same name + different cwd → separate, directory-labeled groups.
    func testBundlelessSameNameDifferentCwdSplits() {
        let samples = [
            sample(1, name: "make", bundle: nil, footprint: 100, ppid: 1,
                   cwd: "/Users/me/hotfix/apps/backend", cmd: "run-api"),
            sample(2, name: "make", bundle: nil, footprint: 200, ppid: 1,
                   cwd: "/Users/me/uitweaks/apps/backend", cmd: "worker"),
        ]
        let groups = AppGrouper().group(samples, topN: 10)
        XCTAssertEqual(groups.count, 2, "different cwd → separate groups")
        let names = Set(groups.map { $0.name })
        XCTAssertTrue(names.contains("make — hotfix/apps/backend (run-api)"))
        XCTAssertTrue(names.contains("make — uitweaks/apps/backend (worker)"))
    }

    // Same name + same cwd → one merged group; representative argv = highest footprint.
    func testBundlelessSameNameSameCwdMerges() {
        let samples = [
            sample(1, name: "make", bundle: nil, footprint: 50, ppid: 1,
                   cwd: "/Users/me/proj/backend", cmd: "small"),
            sample(2, name: "make", bundle: nil, footprint: 500, ppid: 1,
                   cwd: "/Users/me/proj/backend", cmd: "big"),
        ]
        let groups = AppGrouper().group(samples, topN: 10)
        XCTAssertEqual(groups.count, 1, "same name + same cwd merges")
        XCTAssertEqual(groups[0].totalFootprintBytes, 550)
        XCTAssertEqual(groups[0].processCount, 2)
        // Singleton cohort → last component; argv from the heavier process.
        XCTAssertEqual(groups[0].name, "make — backend (big)")
    }

    // Bundle-less + nil cwd → single collapsed bare-name group.
    func testBundlelessNilCwdCollapsesToBareName() {
        let samples = [
            sample(1, name: "make", bundle: nil, footprint: 10, ppid: 1),
            sample(2, name: "make", bundle: nil, footprint: 20, ppid: 1),
        ]
        let groups = AppGrouper().group(samples, topN: 10)
        XCTAssertEqual(groups.count, 1, "unreadable-cwd same-name processes collapse")
        // Note: two spaces before "(" — collapsedLabel intentionally uses a double space.
        XCTAssertEqual(groups[0].name, "make  (2 processes, dir unavailable)")
        XCTAssertEqual(groups[0].totalFootprintBytes, 30)
    }

    // pathStyle: .fullPath produces ~-abbreviated labels regardless of uniqueness.
    func testFullPathStyleProducesHomeAbbreviatedLabels() {
        let samples = [
            sample(1, name: "node", bundle: nil, footprint: 100, ppid: 1,
                   cwd: "/Users/me/svc/api", cmd: "index.js"),
        ]
        let groups = AppGrouper().group(samples, topN: 10, pathStyle: .fullPath,
                                        homeDirectory: "/Users/me")
        XCTAssertEqual(groups[0].name, "node — ~/svc/api (index.js)")
    }
}
