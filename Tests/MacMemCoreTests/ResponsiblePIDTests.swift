import XCTest
@testable import MacMemCore

final class ResponsiblePIDTests: XCTestCase {
    func testDisabledByDefaultReturnsNil() {
        XCTAssertNil(ResponsiblePID.lookup(for: ProcessInfo.processInfo.processIdentifier, enabled: false))
    }

    func testEnabledReturnsValidResponsiblePID() {
        let me = ProcessInfo.processInfo.processIdentifier
        // The private symbol must resolve and return a real, positive pid.
        guard let r = ResponsiblePID.lookup(for: me, enabled: true) else {
            return XCTFail("responsible-pid private symbol returned no pid")
        }
        XCTAssertGreaterThan(r, 0)
        // Responsibility is a fixed point: the process responsible for `me` is
        // its own responsible process. This holds regardless of whether `me` is
        // a top-level process or a helper/subprocess (as XCTest itself is), so
        // it avoids the brittle "responsible pid == self" assumption.
        XCTAssertEqual(ResponsiblePID.lookup(for: r, enabled: true), r)
    }
}
