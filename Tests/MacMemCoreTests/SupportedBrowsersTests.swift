import XCTest
@testable import MacMemCore

final class SupportedBrowsersTests: XCTestCase {

    func testAllContainsFourBrowsers() {
        XCTAssertEqual(SupportedBrowsers.all.count, 4)
    }

    func testCanonicalExactMatch() {
        XCTAssertEqual(SupportedBrowsers.canonical("Brave Browser"), "Brave Browser")
        XCTAssertEqual(SupportedBrowsers.canonical("Google Chrome"), "Google Chrome")
        XCTAssertEqual(SupportedBrowsers.canonical("Microsoft Edge"), "Microsoft Edge")
        XCTAssertEqual(SupportedBrowsers.canonical("Safari"), "Safari")
    }

    func testCanonicalCaseInsensitiveMatch() {
        XCTAssertEqual(SupportedBrowsers.canonical("brave browser"), "Brave Browser")
        XCTAssertEqual(SupportedBrowsers.canonical("SAFARI"), "Safari")
        XCTAssertEqual(SupportedBrowsers.canonical("google chrome"), "Google Chrome")
        XCTAssertEqual(SupportedBrowsers.canonical("microsoft edge"), "Microsoft Edge")
    }

    func testCanonicalUnsupportedReturnsNil() {
        XCTAssertNil(SupportedBrowsers.canonical("Firefox"))
        XCTAssertNil(SupportedBrowsers.canonical(""))
        XCTAssertNil(SupportedBrowsers.canonical("Brave"))
    }
}
