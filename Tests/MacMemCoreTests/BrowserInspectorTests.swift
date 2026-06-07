import XCTest
@testable import MacMemCore

private struct BrowserTestError: Error {}

final class BrowserInspectorTests: XCTestCase {
    func testListsEveryTabPerBrowser() {
        let source = FakeTabSource(byBrowser: [
            "Brave": [RawTab(title: "A", url: "https://a.com", windowIndex: 0, tabIndex: 0),
                      RawTab(title: "B", url: "https://b.com", windowIndex: 0, tabIndex: 1)],
        ])
        var ignored = false
        let browsers = BrowserInspector(source: source).browsers(hadErrors: &ignored)
        XCTAssertEqual(browsers.count, 1)
        XCTAssertEqual(browsers.first?.browser, "Brave")
        XCTAssertEqual(browsers.first?.tabs.map(\.url), ["https://a.com", "https://b.com"])
        // No browserTotals supplied → no attributable total, count 0.
        XCTAssertNil(browsers.first?.totalFootprintBytes)
        XCTAssertEqual(browsers.first?.processCount, 0)
    }

    func testWiresMeasuredTotalFromBrowserTotals() {
        let source = FakeTabSource(byBrowser: [
            "Brave": [RawTab(title: "A", url: "https://a.com", windowIndex: 0, tabIndex: 0)],
        ])
        var ignored = false
        let browsers = BrowserInspector(source: source)
            .browsers(browserTotals: ["Brave": (bytes: 1000, count: 5)], hadErrors: &ignored)
        XCTAssertEqual(browsers.first?.totalFootprintBytes, 1000)
        XCTAssertEqual(browsers.first?.processCount, 5)
    }

    // A browserTotals entry with a nil `bytes` (Safari's unattributable case) must
    // surface as a nil total, not a fabricated number.
    func testNilBytesEntrySurfacesAsNilTotal() {
        let source = FakeTabSource(byBrowser: [
            "Safari": [RawTab(title: "A", url: "https://a.com", windowIndex: 0, tabIndex: 0)],
        ])
        var ignored = false
        let browsers = BrowserInspector(source: source)
            .browsers(browserTotals: ["Safari": (bytes: nil, count: 3)], hadErrors: &ignored)
        XCTAssertNil(browsers.first?.totalFootprintBytes)
        XCTAssertEqual(browsers.first?.processCount, 3)
    }

    func testPartialBrowserFailureReturnsSuccessfulBrowsersAndSignalsError() {
        // Browser A returns 2 tabs; browser B throws.
        // browsers() must return A AND signal that something failed.
        let source = FakeTabSource(
            byBrowser: [
                "BrowserA": [RawTab(title: "A1", url: "https://a1.com", windowIndex: 0, tabIndex: 0),
                              RawTab(title: "A2", url: "https://a2.com", windowIndex: 0, tabIndex: 1)],
                "BrowserB": [],
            ],
            errorsByBrowser: ["BrowserB": BrowserTestError()])

        var hadPartialError = false
        let browsers = BrowserInspector(source: source).browsers(hadErrors: &hadPartialError)
        XCTAssertEqual(browsers.map(\.browser), ["BrowserA"])
        XCTAssertEqual(browsers.first?.tabs.count, 2)
        XCTAssertTrue(hadPartialError, "hadErrors must be true when any browser fails")
    }

    func testAllBrowsersSucceedHadErrorsFalse() {
        let source = FakeTabSource(byBrowser: [
            "BrowserA": [RawTab(title: "A", url: "https://a.com", windowIndex: 0, tabIndex: 0)],
        ])
        var hadPartialError = false
        let browsers = BrowserInspector(source: source).browsers(hadErrors: &hadPartialError)
        XCTAssertEqual(browsers.count, 1)
        XCTAssertFalse(hadPartialError, "hadErrors must be false when all browsers succeed")
    }

    // browsers() must be non-throwing — this test deliberately omits `try` and will
    // fail to compile if a `throws` annotation creeps back in.
    func testBrowsersIsNonThrowing() {
        let source = FakeTabSource(byBrowser: [
            "Brave": [RawTab(title: "A", url: "https://a.com", windowIndex: 0, tabIndex: 0)],
        ])
        var ignored = false
        let browsers = BrowserInspector(source: source).browsers(hadErrors: &ignored)
        XCTAssertEqual(browsers.count, 1)
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

    // Regression guard: inside a `tell application "<browser>"` block the bare keyword
    // `tab` resolves to the app's `tab` *class*, not the tab character — so `& tab &`
    // emits the literal text "tab" and every output line becomes unparseable. The
    // delimiter must therefore be bound to `tab` OUTSIDE the tell block and referenced
    // by variable inside it. (This bug silently produced zero tabs for all browsers.)
    func testScriptsBindTabDelimiterOutsideTellBlock() {
        for script in [AppleScriptTabSource.chromiumScript(app: "Brave Browser"),
                       AppleScriptTabSource.safariScript] {
            let tellRange = try! XCTUnwrap(script.range(of: "tell application"))
            let preamble = script[..<tellRange.lowerBound]
            let body = script[tellRange.lowerBound...]
            XCTAssertTrue(preamble.contains("set d to tab"),
                          "delimiter must be bound to `tab` before the tell block")
            XCTAssertFalse(body.contains("& tab &"),
                           "must not use the bare `tab` keyword as a separator inside the tell block")
            XCTAssertTrue(body.contains("& d &"),
                          "must use the pre-bound delimiter variable inside the tell block")
        }
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
