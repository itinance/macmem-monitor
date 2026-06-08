import XCTest
import SwiftUI
@testable import MacMemMenuBar
@testable import MacMemCore

final class PressureStyleTests: XCTestCase {
    func testSymbolPerLevel() {
        XCTAssertEqual(PressureStyle.symbolName(for: .normal), "memorychip")
        XCTAssertEqual(PressureStyle.symbolName(for: .warn), "memorychip")
        XCTAssertEqual(PressureStyle.symbolName(for: .critical), "memorychip.fill")
        XCTAssertEqual(PressureStyle.symbolName(for: .unknown), "memorychip")
    }

    func testTintPerLevel() {
        XCTAssertEqual(PressureStyle.tint(for: .normal), .green)
        XCTAssertEqual(PressureStyle.tint(for: .warn), .yellow)
        XCTAssertEqual(PressureStyle.tint(for: .critical), .red)
        XCTAssertEqual(PressureStyle.tint(for: .unknown), .secondary)
    }
}
