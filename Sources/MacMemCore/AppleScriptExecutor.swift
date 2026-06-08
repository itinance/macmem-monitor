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

    /// How long to wait for a single script before giving up. A wedged Apple Event (a
    /// browser blocked on a modal sheet, a TCC prompt race) must not freeze the caller
    /// forever: BrowserInspector only reaches its `.partial` fallback if `tabs(for:)`
    /// throws, so a bounded wait turns non-responsiveness into a recoverable error.
    static let defaultTimeout: TimeInterval = 10

    /// Compile and run `source`, returning its string result. Blocks the CALLING thread
    /// until the script finishes or `timeout` elapses — callers must invoke this off the
    /// main thread (the tab pass already runs inside a detached task). Throws on
    /// compile/exec failure, or `TabError.timedOut` if the script does not return in time.
    ///
    /// On timeout the worker thread may still be stuck inside the unresponsive script, so
    /// the *next* call queues behind it — but the caller fails fast and the remaining
    /// browsers are reported, which is the behaviour BrowserInspector relies on.
    func run(_ source: String, timeout: TimeInterval = AppleScriptExecutor.defaultTimeout) throws -> String {
        var outcome: Result<String, Error> = .failure(TabError.compileFailed)
        let done = DispatchSemaphore(value: 0)
        let box = ClosureBox {
            outcome = Result { try Self.execute(source) }
            done.signal()
        }
        perform(#selector(runBox(_:)), on: thread, with: box, waitUntilDone: false)
        guard done.wait(timeout: .now() + timeout) == .success else { throw TabError.timedOut }
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
