import Foundation
import AppKit
import MacMemCore

/// Real system-effecting actions. Quitting is limited to the current user's apps
/// (no privileged helper); purge uses a one-shot admin prompt; nothing persists.
@MainActor
public final class LiveSystemActions: SystemActions {
    public init() {}

    /// Snapshot of running apps as pure candidates, for `AppResolver`.
    public static func currentCandidates() -> [AppCandidate] {
        NSWorkspace.shared.runningApplications.map {
            AppCandidate(bundleID: $0.bundleIdentifier, pid: $0.processIdentifier)
        }
    }

    public func quit(app: AppGroup) async -> ActionResult {
        let running = NSWorkspace.shared.runningApplications
        let candidates = running.map {
            AppCandidate(bundleID: $0.bundleIdentifier, pid: $0.processIdentifier)
        }
        // Resolve which running app the group refers to (pure logic), then map the
        // matched candidate back to its NSRunningApplication by pid to terminate it.
        guard let candidate = AppResolver.match(group: app, candidates: candidates),
              let target = running.first(where: { $0.processIdentifier == candidate.pid }) else {
            return .notPermitted   // not one of the current user's GUI apps
        }
        return target.terminate() ? .ok : .failed("Could not quit \(app.name).")
    }

    public func purge() async -> ActionResult {
        let source = "do shell script \"/usr/sbin/purge\" with administrator privileges"
        guard let script = NSAppleScript(source: source) else {
            return .failed("Could not build purge script.")
        }
        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        guard let errorInfo else { return .ok }
        // -128 is userCancelledErr (the admin sheet was dismissed).
        if (errorInfo[NSAppleScript.errorNumber] as? Int) == -128 { return .cancelled }
        let msg = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "purge failed"
        return .failed(msg)
    }

    public func revealInActivityMonitor(app: AppGroup) {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    public func copySnapshot(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}
