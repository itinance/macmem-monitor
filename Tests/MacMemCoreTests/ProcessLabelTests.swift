import XCTest
@testable import MacMemCore

final class ProcessLabelTests: XCTestCase {
    // groupKey: three cases from the spec.
    func testGroupKeyUsesBaseBundleIDWhenPresent() {
        XCTAssertEqual(
            ProcessLabel.groupKey(name: "Brave Browser", baseBundleID: "com.brave.Browser",
                                  workingDirectory: "/anywhere"),
            "com.brave.Browser")
    }

    func testGroupKeySplitsBundlelessByDirectory() {
        let a = ProcessLabel.groupKey(name: "make", baseBundleID: nil, workingDirectory: "/x/a")
        let b = ProcessLabel.groupKey(name: "make", baseBundleID: nil, workingDirectory: "/x/b")
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a, ProcessLabel.groupKey(name: "make", baseBundleID: nil, workingDirectory: "/x/a"))
    }

    func testGroupKeyBundlelessNilCwdCollapsesToName() {
        XCTAssertEqual(
            ProcessLabel.groupKey(name: "make", baseBundleID: nil, workingDirectory: nil),
            "make")
    }

    func testShortestUniqueSuffixesDisambiguatesCommonTail() {
        let result = ProcessLabel.shortestUniqueSuffixes([
            "/Users/me/hotfix/apps/backend",
            "/Users/me/uitweaks/apps/backend",
        ])
        XCTAssertEqual(result["/Users/me/hotfix/apps/backend"], "hotfix/apps/backend")
        XCTAssertEqual(result["/Users/me/uitweaks/apps/backend"], "uitweaks/apps/backend")
    }

    func testShortestUniqueSuffixesSingletonIsLastComponent() {
        let result = ProcessLabel.shortestUniqueSuffixes(["/Users/me/project/backend"])
        XCTAssertEqual(result["/Users/me/project/backend"], "backend")
    }

    func testShortestUniqueSuffixesSuffixOfSuffixFallsBack() {
        let result = ProcessLabel.shortestUniqueSuffixes(["/a/b/c", "/b/c"])
        XCTAssertNil(result["/b/c"])
        XCTAssertEqual(result["/a/b/c"], "a/b/c")
    }

    func testAbbreviateHomeReplacesPrefix() {
        XCTAssertEqual(ProcessLabel.abbreviateHome("/Users/me/x/y", home: "/Users/me"), "~/x/y")
        XCTAssertEqual(ProcessLabel.abbreviateHome("/Users/me", home: "/Users/me"), "~")
        XCTAssertEqual(ProcessLabel.abbreviateHome("/opt/tool", home: "/Users/me"), "/opt/tool")
    }

    func testDisplayLabelWithDirAndRawArgv() {
        XCTAssertEqual(
            ProcessLabel.displayLabel(name: "make", dirDisplay: "apps/backend", commandLine: "-j8 run-api"),
            "make — apps/backend (-j8 run-api)")
    }

    func testDisplayLabelWithDirNoArgv() {
        XCTAssertEqual(
            ProcessLabel.displayLabel(name: "make", dirDisplay: "apps/backend", commandLine: nil),
            "make — apps/backend")
    }

    func testCollapsedLabelPluralizes() {
        XCTAssertEqual(ProcessLabel.collapsedLabel(name: "make", processCount: 1),
                       "make  (1 process, dir unavailable)")
        XCTAssertEqual(ProcessLabel.collapsedLabel(name: "make", processCount: 3),
                       "make  (3 processes, dir unavailable)")
    }

    func testShortestUniqueSuffixesThreeWayCommonTail() {
        let result = ProcessLabel.shortestUniqueSuffixes([
            "/Users/me/a/apps/backend",
            "/Users/me/x/apps/backend",
            "/Users/me/y/apps/backend",
        ])
        XCTAssertEqual(result["/Users/me/a/apps/backend"], "a/apps/backend")
        XCTAssertEqual(result["/Users/me/x/apps/backend"], "x/apps/backend")
        XCTAssertEqual(result["/Users/me/y/apps/backend"], "y/apps/backend")
    }
}
