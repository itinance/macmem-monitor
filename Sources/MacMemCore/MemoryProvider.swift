import Foundation

public protocol MemoryProvider: Sendable {
    /// Returns one sample per visible process. Unreadable processes are still
    /// returned with `isReadable == false` and zeroed memory fields.
    func listProcesses() throws -> [ProcessSample]
    func readSwap() throws -> SwapInfo
}

public struct FakeMemoryProvider: MemoryProvider {
    public var processes: [ProcessSample]
    public var swap: SwapInfo
    public var processError: Error?
    public var swapError: Error?

    public init(processes: [ProcessSample], swap: SwapInfo,
                processError: Error? = nil, swapError: Error? = nil) {
        self.processes = processes; self.swap = swap
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
}
