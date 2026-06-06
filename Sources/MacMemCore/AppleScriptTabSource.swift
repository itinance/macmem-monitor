import Foundation
import AppKit

/// Reads browser tabs via AppleScript. Triggers a one-time macOS Automation
/// (TCC) prompt per browser. On denial/error, throws so SnapshotBuilder marks
/// the tabs section `.partial`.
public struct AppleScriptTabSource: TabSource {
    private let candidates: [String]
    public init(candidates: [String] = ["Brave Browser", "Google Chrome", "Microsoft Edge", "Safari"]) {
        self.candidates = candidates
    }

    /// NSWorkspace is main-thread-affined; hop to main when called off-main to
    /// avoid undefined behaviour. Same pattern as NativeMemoryProvider.appIdentityByPID().
    public func runningBrowsers() -> [String] {
        if Thread.isMainThread {
            return collectRunningBrowsers()
        } else {
            return DispatchQueue.main.sync { collectRunningBrowsers() }
        }
    }

    private func collectRunningBrowsers() -> [String] {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.localizedName })
        return candidates.filter { running.contains($0) }
    }

    public func tabs(for browser: String) throws -> [RawTab] {
        guard Self.isSafeBrowserName(browser) else { throw TabError.unsafeBrowserName(browser) }
        let script = browser == "Safari" ? Self.safariScript : Self.chromiumScript(app: browser)
        let output = try runAppleScript(script)
        return Self.parse(output)
    }

    /// Browser names are interpolated into AppleScript source, so restrict them
    /// to a safe character set (letters, digits, spaces, dots) to prevent
    /// AppleScript injection via the public `init(candidates:)`.
    static func isSafeBrowserName(_ name: String) -> Bool {
        !name.isEmpty && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == " " || $0 == "." }
    }

    // Output format: one tab per line as "windowIndex\ttabIndex\tURL\tTITLE"
    private static func chromiumScript(app: String) -> String {
        """
        set out to ""
        tell application "\(app)"
            set wi to 0
            repeat with w in windows
                set ti to 0
                repeat with t in tabs of w
                    set out to out & wi & tab & ti & tab & (URL of t) & tab & (title of t) & linefeed
                    set ti to ti + 1
                end repeat
                set wi to wi + 1
            end repeat
        end tell
        return out
        """
    }

    private static let safariScript = """
        set out to ""
        tell application "Safari"
            set wi to 0
            repeat with w in windows
                set ti to 0
                repeat with t in tabs of w
                    set out to out & wi & tab & ti & tab & (URL of t) & tab & (name of t) & linefeed
                    set ti to ti + 1
                end repeat
                set wi to wi + 1
            end repeat
        end tell
        return out
        """

    private func runAppleScript(_ source: String) throws -> String {
        if Thread.isMainThread {
            return try executeAppleScript(source)
        } else {
            // NSAppleScript is main-thread-affined; hop to main when called off-main.
            return try DispatchQueue.main.sync { try executeAppleScript(source) }
        }
    }

    private func executeAppleScript(_ source: String) throws -> String {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { throw TabError.compileFailed }
        let result = script.executeAndReturnError(&error)
        if let error { throw TabError.execFailed(String(describing: error)) }
        return result.stringValue ?? ""
    }

    static func parse(_ raw: String) -> [RawTab] {
        raw.split(separator: "\n").compactMap { line in
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 4,
                  let wi = Int(parts[0]), let ti = Int(parts[1]) else { return nil }
            let url = parts[2]
            let title = parts[3...].joined(separator: "\t")
            guard !url.isEmpty else { return nil }
            return RawTab(title: title, url: url, windowIndex: wi, tabIndex: ti)
        }
    }
}

enum TabError: Error {
    case compileFailed
    case execFailed(String)
    case unsafeBrowserName(String)
}
