import XCTest
@testable import MacMemCore

final class BrowserInspectorTests: XCTestCase {
    func testListsTabsWithoutEstimatesWhenNoRendererData() throws {
        let source = FakeTabSource(byBrowser: [
            "Brave": [RawTab(title: "A", url: "https://a.com", windowIndex: 0, tabIndex: 0),
                      RawTab(title: "B", url: "https://b.com", windowIndex: 0, tabIndex: 1)],
        ])
        let tabs = try BrowserInspector(source: source).topTabs(rendererFootprintsByBrowser: [:], topN: 10)
        XCTAssertEqual(tabs.count, 2)
        XCTAssertTrue(tabs.allSatisfy { $0.estimatedBytes == nil })
        XCTAssertTrue(tabs.allSatisfy { $0.confidence == .low })
    }

    func testCountMatchEnablesEstimatesAndHeaviestOrdering() throws {
        let source = FakeTabSource(byBrowser: [
            "Brave": [RawTab(title: "A", url: "https://a.com", windowIndex: 0, tabIndex: 0),
                      RawTab(title: "B", url: "https://b.com", windowIndex: 0, tabIndex: 1)],
        ])
        let tabs = try BrowserInspector(source: source)
            .topTabs(rendererFootprintsByBrowser: ["Brave": [100, 500]], topN: 10)
        XCTAssertEqual(tabs.count, 2)
        XCTAssertEqual(tabs[0].estimatedBytes, 500)
        XCTAssertEqual(tabs[1].estimatedBytes, 100)
    }

    func testCountMismatchLeavesEstimatesBlank() throws {
        let source = FakeTabSource(byBrowser: [
            "Brave": [RawTab(title: "A", url: "https://a.com", windowIndex: 0, tabIndex: 0),
                      RawTab(title: "B", url: "https://b.com", windowIndex: 0, tabIndex: 1)],
        ])
        let tabs = try BrowserInspector(source: source)
            .topTabs(rendererFootprintsByBrowser: ["Brave": [500]], topN: 10)
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
}
