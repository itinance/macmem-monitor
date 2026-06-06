import XCTest
@testable import MacMemCore

private struct BrowserTestError: Error {}

final class BrowserInspectorTests: XCTestCase {
    func testListsTabsWithoutEstimatesWhenNoRendererData() throws {
        let source = FakeTabSource(byBrowser: [
            "Brave": [RawTab(title: "A", url: "https://a.com", windowIndex: 0, tabIndex: 0),
                      RawTab(title: "B", url: "https://b.com", windowIndex: 0, tabIndex: 1)],
        ])
        var ignored = false
        let tabs = try BrowserInspector(source: source)
            .topTabs(rendererFootprintsByBrowser: [:], topN: 10, hadErrors: &ignored)
        XCTAssertEqual(tabs.count, 2)
        XCTAssertTrue(tabs.allSatisfy { $0.estimatedBytes == nil })
        XCTAssertTrue(tabs.allSatisfy { $0.confidence == .low })
    }

    func testCountMatchEnablesEstimatesAndHeaviestOrdering() throws {
        let source = FakeTabSource(byBrowser: [
            "Brave": [RawTab(title: "A", url: "https://a.com", windowIndex: 0, tabIndex: 0),
                      RawTab(title: "B", url: "https://b.com", windowIndex: 0, tabIndex: 1)],
        ])
        var ignored = false
        let tabs = try BrowserInspector(source: source)
            .topTabs(rendererFootprintsByBrowser: ["Brave": [100, 500]], topN: 10, hadErrors: &ignored)
        XCTAssertEqual(tabs.count, 2)
        XCTAssertEqual(tabs[0].estimatedBytes, 500)
        XCTAssertEqual(tabs[1].estimatedBytes, 100)
    }

    func testPartialBrowserFailureReturnsSuccessfulBrowserTabsAndThrows() throws {
        // Browser A returns 2 tabs; browser B throws.
        // topTabs must return A's 2 tabs AND signal that something failed.
        let source = FakeTabSource(
            byBrowser: [
                "BrowserA": [RawTab(title: "A1", url: "https://a1.com", windowIndex: 0, tabIndex: 0),
                              RawTab(title: "A2", url: "https://a2.com", windowIndex: 0, tabIndex: 1)],
                "BrowserB": [],
            ],
            errorsByBrowser: ["BrowserB": BrowserTestError()])

        var hadPartialError = false
        let tabs = try BrowserInspector(source: source)
            .topTabs(rendererFootprintsByBrowser: [:], topN: 10, hadErrors: &hadPartialError)
        XCTAssertEqual(tabs.count, 2)
        XCTAssertTrue(tabs.allSatisfy { $0.browser == "BrowserA" })
        XCTAssertTrue(hadPartialError, "hadErrors must be true when any browser fails")
    }

    func testAllBrowsersSucceedHadErrorsFalse() throws {
        let source = FakeTabSource(byBrowser: [
            "BrowserA": [RawTab(title: "A", url: "https://a.com", windowIndex: 0, tabIndex: 0)],
        ])
        var hadPartialError = false
        let tabs = try BrowserInspector(source: source)
            .topTabs(rendererFootprintsByBrowser: [:], topN: 10, hadErrors: &hadPartialError)
        XCTAssertEqual(tabs.count, 1)
        XCTAssertFalse(hadPartialError, "hadErrors must be false when all browsers succeed")
    }

    func testCountMismatchLeavesEstimatesBlank() throws {
        let source = FakeTabSource(byBrowser: [
            "Brave": [RawTab(title: "A", url: "https://a.com", windowIndex: 0, tabIndex: 0),
                      RawTab(title: "B", url: "https://b.com", windowIndex: 0, tabIndex: 1)],
        ])
        var ignored = false
        let tabs = try BrowserInspector(source: source)
            .topTabs(rendererFootprintsByBrowser: ["Brave": [500]], topN: 10, hadErrors: &ignored)
        XCTAssertTrue(tabs.allSatisfy { $0.estimatedBytes == nil })
    }
}

extension BrowserInspectorTests {
    func testAppleScriptOutputParsing() {
        let raw = "0\t0\thttps://a.com\tAlpha\n0\t1\thttps://b.com\tBeta\textra\n0\t2\t\tEmptyURL\n"
        let tabs = AppleScriptTabSource.parse(raw)
        XCTAssertEqual(tabs.count, 2)                       // empty-URL line dropped
        XCTAssertEqual(tabs[0].url, "https://a.com")
        XCTAssertEqual(tabs[0].title, "Alpha")
        XCTAssertEqual(tabs[1].title, "Beta\textra")        // tab-in-title preserved
    }

    func testRejectsUnsafeBrowserNames() {
        XCTAssertTrue(AppleScriptTabSource.isSafeBrowserName("Brave Browser"))
        XCTAssertTrue(AppleScriptTabSource.isSafeBrowserName("Google Chrome"))
        XCTAssertFalse(AppleScriptTabSource.isSafeBrowserName("\") end tell\ndo shell script \"rm\"\ntell application (\""))
        XCTAssertFalse(AppleScriptTabSource.isSafeBrowserName(""))
        XCTAssertThrowsError(try AppleScriptTabSource().tabs(for: "evil\"name")) { error in
            guard case TabError.unsafeBrowserName = error else {
                return XCTFail("expected unsafeBrowserName, got \(error)")
            }
        }
    }
}
