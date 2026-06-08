import Foundation
import Darwin

public protocol MemoryProvider: Sendable {
    /// Returns one sample per visible process. Unreadable processes are still
    /// returned with `isReadable == false` and zeroed memory fields.
    func listProcesses() throws -> [ProcessSample]
    func readSwap() throws -> SwapInfo
    /// Returns a map of pid → measured compressed bytes from top(1) CMPRS column.
    /// `throws` for forward-compat: a future sysctl-based source may throw; the current
    /// top-based impl absorbs all failures internally and returns `[:]` on error.
    func compressedByPID() throws -> [pid_t: UInt64]
    /// Current OS memory-pressure level. Non-throwing: returns `.unknown` on any
    /// failure so the UI never shows a fabricated level.
    func pressure() -> MemoryPressure
}

public struct FakeMemoryProvider: MemoryProvider {
    public var processes: [ProcessSample]
    public var swap: SwapInfo
    public var compressed: [pid_t: UInt64]
    public var processError: Error?
    public var swapError: Error?
    public var pressureValue: MemoryPressure = .normal

    public init(processes: [ProcessSample], swap: SwapInfo,
                compressed: [pid_t: UInt64] = [:],
                processError: Error? = nil, swapError: Error? = nil) {
        self.processes = processes; self.swap = swap
        self.compressed = compressed
        self.processError = processError; self.swapError = swapError
    }

    public func listProcesses() throws -> [ProcessSample] {
        if let processError { throw processError }
        return processes
    }
    public func readSwap() throws -> SwapInfo {
        if let swapError { throw swapError }
        return swap
    }
    public func compressedByPID() throws -> [pid_t: UInt64] {
        compressed
    }
    public func pressure() -> MemoryPressure { pressureValue }
}
