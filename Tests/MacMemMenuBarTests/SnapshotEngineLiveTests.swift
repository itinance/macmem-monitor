import XCTest
@testable import MacMemMenuBar
@testable import MacMemCore

/// Integration guard: drives one OPEN-mode tick through the engine with the REAL
/// NativeMemoryProvider. listProcesses() runs inside tick()'s `Task.detached` and
/// internally hops to the main actor for NSWorkspace identity. If a @MainActor await
/// genuinely deadlocked against that main-queue hop, this test would hang and time out.
/// It completing — and delivering a snapshot — proves the off-main sampling path is safe.
@MainActor
final class SnapshotEngineLiveTests: XCTestCase {
    func testOpenTickCompletesWithRealProviderNoDeadlock() async {
        let provider = NativeMemoryProvider()
        var delivered: MemorySnapshot?
        let engine = SnapshotEngine(provider: provider, tabSource: nil, topN: 5)
        engine.onSnapshot = { delivered = $0 }
        engine.setMode(.open)
        await engine.tick()
        XCTAssertNotNil(delivered, "open-mode tick must deliver a snapshot via onSnapshot")
        XCTAssertFalse(delivered?.topApps.isEmpty ?? true, "the live machine has running apps")
    }
}
