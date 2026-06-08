import Foundation

/// Runs NSAppleScript on a single, long-lived background thread that owns a run loop.
///
/// Apple Events are sent synchronously and need a run loop on the calling thread to
/// receive their reply — which is why the naive approach runs them on the main thread.
/// But enumerating hundreds of browser tabs takes several seconds, and doing that on main
/// freezes the menu. Running on a dedicated worker thread with its own run loop satisfies
/// the Apple Event machinery while leaving the main thread free. NSAppleScript is not
/// thread-safe, so every script is serialized onto this one thread.
final class AppleScriptExecutor: NSObject, @unchecked Sendable {
    static let shared = AppleScriptExecutor()

    private let thread: RunLoopThread

    private override init() {
        thread = RunLoopThread()
        thread.name = "sh.macmem.applescript"
        thread.stackSize = 4 << 20
        super.init()
        thread.start()
    }

    /// Compile and run `source`, returning its string result. Blocks the CALLING thread
    /// until the script finishes — callers must invoke this off the main thread (the tab
    /// pass already runs inside a detached task). Throws on compile/exec failure.
    func run(_ source: String) throws -> String {
        var outcome: Result<String, Error> = .failure(TabError.compileFailed)
        let box = ClosureBox { outcome = Result { try Self.execute(source) } }
        perform(#selector(runBox(_:)), on: thread, with: box, waitUntilDone: true)
        return try outcome.get()
    }

    @objc private func runBox(_ box: ClosureBox) { box.work() }

    private static func execute(_ source: String) throws -> String {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { throw TabError.compileFailed }
        let result = script.executeAndReturnError(&error)
        if let error { throw TabError.execFailed(String(describing: error)) }
        return result.stringValue ?? ""
    }
}

/// A thread whose `main` keeps a run loop spinning until cancelled. The mach port is an
/// input source that gives the run loop a reason not to exit immediately when idle.
private final class RunLoopThread: Thread {
    override func main() {
        let runLoop = RunLoop.current
        runLoop.add(NSMachPort(), forMode: .default)
        while !isCancelled {
            runLoop.run(mode: .default, before: .distantFuture)
        }
    }
}

/// Boxes a closure so it can ride through `perform(_:on:with:waitUntilDone:)`. Subclasses
/// NSObject so it bridges to the `id` argument that `#selector(runBox(_:))` expects.
private final class ClosureBox: NSObject {
    let work: () -> Void
    init(_ work: @escaping () -> Void) { self.work = work }
}
