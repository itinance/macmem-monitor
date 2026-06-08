import XCTest
@testable import MacMemCore

final class MemoryPressureTests: XCTestCase {
    func testRawLevelMapping() {
        XCTAssertEqual(MemoryPressure(rawLevel: 1), .normal)
        XCTAssertEqual(MemoryPressure(rawLevel: 2), .warn)
        XCTAssertEqual(MemoryPressure(rawLevel: 4), .critical)
        XCTAssertEqual(MemoryPressure(rawLevel: 0), .unknown)
        XCTAssertEqual(MemoryPressure(rawLevel: 3), .unknown)
        XCTAssertEqual(MemoryPressure(rawLevel: 99), .unknown)
    }

    func testFakeProviderReturnsConfiguredPressure() {
        var provider = FakeMemoryProvider(
            processes: [], swap: SwapInfo(totalBytes: 0, usedBytes: 0, freeBytes: 0, swapIns: 0, swapOuts: 0))
        provider.pressureValue = .critical
        XCTAssertEqual(provider.pressure(), .critical)
    }

    func testFakeProviderDefaultPressureIsNormal() {
        let provider = FakeMemoryProvider(
            processes: [], swap: SwapInfo(totalBytes: 0, usedBytes: 0, freeBytes: 0, swapIns: 0, swapOuts: 0))
        XCTAssertEqual(provider.pressure(), .normal)
    }
}
