import XCTest
@testable import MacMemCore

final class SmokeTests: XCTestCase {
    func testVersionExists() {
        XCTAssertFalse(MacMemCore.version.isEmpty)
    }
}
