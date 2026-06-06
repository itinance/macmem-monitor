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

    func run() throws {
        if let interval = watch {
            while true {
                printOnce(clear: true)
                Thread.sleep(forTimeInterval: max(0.5, interval))
            }
        } else {
            printOnce(clear: false)
        }
    }

    private func printOnce(clear: Bool) {
        if clear { print("\u{001B}[2J\u{001B}[H", terminator: "") }

        let provider = NativeMemoryProvider(useResponsiblePID: responsiblePid)
        let tabSource: TabSource? = noTabs ? nil : AppleScriptTabSource()
        let snapshot = SnapshotBuilder(provider: provider, tabSource: tabSource)
            .build(topN: top, includeTabs: !noTabs, includeSwap: !noSwap)

        if json {
            if let out = try? JSONRenderer.render(snapshot) { print(out) }
        } else {
            print(TextRenderer.render(snapshot))
        }

        printPrivilegeHintIfNeeded(snapshot)
    }

    private func printPrivilegeHintIfNeeded(_ snapshot: MemorySnapshot) {
        if geteuid() != 0 && snapshot.unreadableProcessCount > 0 {
            FileHandle.standardError.write(Data(
                "\n\(snapshot.unreadableProcessCount) processes not readable — run `sudo macmem` for full coverage.\n".utf8))
        }
    }
}

Macmem.main()
