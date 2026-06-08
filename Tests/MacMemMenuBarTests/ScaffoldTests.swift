import XCTest
@testable import MacMemMenuBar

final class ScaffoldTests: XCTestCase {
    func testTargetLinks() {
        XCTAssertTrue(MacMemMenuBarBuildMarker.ok)
    }
}
