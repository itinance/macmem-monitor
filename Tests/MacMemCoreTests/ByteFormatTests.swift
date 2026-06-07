import XCTest
@testable import MacMemCore

final class ByteFormatTests: XCTestCase {
    func testFormatsBinaryUnits() {
        XCTAssertEqual(ByteFormat.string(512), "512 B")
        XCTAssertEqual(ByteFormat.string(1024), "1.0 KB")
        XCTAssertEqual(ByteFormat.string(1_572_864), "1.5 MB")
        XCTAssertEqual(ByteFormat.string(2_147_483_648), "2.0 GB")
    }
}
