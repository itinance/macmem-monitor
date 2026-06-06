import ArgumentParser
import Darwin
import Foundation
import MacMemCore

struct Macmem: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "macmem",
        abstract: "Show the heaviest apps, swap usage, and browser tabs on macOS."
    )

    @Option(name: .shortAndLong, help: "How many items per section.")
    var top: Int = 10

    @Flag(name: .long, help: "Emit JSON instead of a table.")
    var json = false

    @Flag(name: .long, help: "Skip the browser tabs section.")
    var noTabs = false

    @Flag(name: .long, help: "Skip the swap section.")
    var noSwap = false

    @Option(name: .long, help: "Repeat every N seconds (live view).")
    var watch: Double?

    @Flag(name: .long, help: "Use the private responsible-PID API for better grouping (off by default).")
    var responsiblePid = false

    @Option(name: .long, help: "Only read tabs from this browser (Brave Browser, Google Chrome, Microsoft Edge, or Safari).")
    var browser: String?

    func validate() throws {
        if top < 0 {
            throw ValidationError("--top must be >= 0.")
        }
        if let b = browser, SupportedBrowsers.canonical(b) == nil {
            throw ValidationError("Unsupported browser '\(b)'. Supported: \(SupportedBrowsers.all.joined(separator: ", ")).")
        }
    }

    func run() throws {
        if let interval = watch {
            // In watch mode never exit on a single failed iteration — keep looping.
            while true {
                printOnce(clear: true)
                Thread.sleep(forTimeInterval: max(0.5, interval))
            }
        } else {
            let code = printOnce(clear: false)
            if code != 0 { Darwin.exit(code) }
        }
    }

    /// Renders and prints one snapshot. Returns the appropriate exit code.
    @discardableResult
    private func printOnce(clear: Bool) -> Int32 {
        if clear { print("\u{001B}[2J\u{001B}[H", terminator: "") }

        let provider = NativeMemoryProvider(useResponsiblePID: responsiblePid)
        let tabSource: TabSource?
        if noTabs {
            tabSource = nil
        } else if let b = browser, let canonical = SupportedBrowsers.canonical(b) {
            tabSource = AppleScriptTabSource(candidates: [canonical])
        } else {
            tabSource = AppleScriptTabSource()
        }
        let snapshot = SnapshotBuilder(provider: provider, tabSource: tabSource)
            .build(topN: top, includeTabs: !noTabs, includeSwap: !noSwap)

        var renderExitCode: Int32 = 0
        if json {
            do {
                print(try JSONRenderer.render(snapshot))
            } catch {
                FileHandle.standardError.write(Data("Error encoding JSON: \(error)\n".utf8))
                renderExitCode = 1
            }
        } else {
            print(TextRenderer.render(snapshot, includeSwap: !noSwap, includeTabs: !noTabs))
        }

        printPrivilegeHintIfNeeded(snapshot)
        return max(snapshotExitCode(snapshot), renderExitCode)
    }

    private func printPrivilegeHintIfNeeded(_ snapshot: MemorySnapshot) {
        if geteuid() != 0 && snapshot.unreadableProcessCount > 0 {
            FileHandle.standardError.write(Data(
                "\n\(snapshot.unreadableProcessCount) processes not readable — run `sudo macmem` for full coverage.\n".utf8))
        }
        // When running as root, AppleScript / GUI-app enumeration is unavailable so the
        // browser-tabs section will always appear empty.  Emit a targeted hint so the user
        // knows this is a privilege issue, not "no heavy tabs".
        if geteuid() == 0 && !noTabs {
            FileHandle.standardError.write(Data(
                "Browser tabs can't be read as root — run macmem without sudo (and grant Automation access) to list tabs.\n".utf8))
        }
    }
}

Macmem.main()
