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
        // Delivery alone proves the no-deadlock objective. We deliberately do NOT assert
        // topApps is non-empty: that couples the test to the host having visible processes,
        // which can be false on minimal/headless CI runners.
        XCTAssertNotNil(delivered, "open-mode tick must deliver a snapshot via onSnapshot")
    }
}
