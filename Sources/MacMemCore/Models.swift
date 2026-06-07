import Foundation

public enum Confidence: String, Sendable, Codable, Equatable {
    case high, medium, low
}

public enum SectionStatus: String, Sendable, Codable, Equatable {
    case ok, partial, permissionNeeded, error
}

public struct ProcessSample: Sendable, Equatable, Codable {
    public let pid: Int32
    public let ppid: Int32
    public let responsiblePID: Int32?
    public let bundleID: String?
    public let name: String
    public let executablePath: String?
    public let footprintBytes: UInt64
    public let residentBytes: UInt64
    public let pageIns: UInt64
    public let isReadable: Bool
    /// Absolute current working directory, best-effort. `nil` when unreadable (other
    /// users' processes without sudo, or any error). Used to disambiguate CLI groups.
    public let workingDirectory: String?
    /// Raw process arguments after the executable path, space-joined and trimmed.
    /// `nil` when unreadable or empty. For `make -j8 run-api` this is `-j8 run-api`.
    public let commandLine: String?

    public init(pid: Int32, ppid: Int32, responsiblePID: Int32?, bundleID: String?,
                name: String, executablePath: String?, footprintBytes: UInt64,
                residentBytes: UInt64, pageIns: UInt64, isReadable: Bool,
                workingDirectory: String? = nil, commandLine: String? = nil) {
        self.pid = pid; self.ppid = ppid; self.responsiblePID = responsiblePID
        self.bundleID = bundleID; self.name = name; self.executablePath = executablePath
        self.footprintBytes = footprintBytes; self.residentBytes = residentBytes
        self.pageIns = pageIns; self.isReadable = isReadable
        self.workingDirectory = workingDirectory; self.commandLine = commandLine
    }
}

public struct AppGroup: Sendable, Equatable, Codable {
    public let name: String
    public let bundleID: String?
    public let totalFootprintBytes: UInt64
    public let processCount: Int
    public let pids: [Int32]

    public init(name: String, bundleID: String?, totalFootprintBytes: UInt64,
                processCount: Int, pids: [Int32]) {
        self.name = name; self.bundleID = bundleID
        self.totalFootprintBytes = totalFootprintBytes
        self.processCount = processCount; self.pids = pids
    }
}

public struct SwapInfo: Sendable, Equatable, Codable {
    public let totalBytes: UInt64
    public let usedBytes: UInt64
    public let freeBytes: UInt64
    public let swapIns: UInt64
    public let swapOuts: UInt64

    public init(totalBytes: UInt64, usedBytes: UInt64, freeBytes: UInt64,
                swapIns: UInt64, swapOuts: UInt64) {
        self.totalBytes = totalBytes; self.usedBytes = usedBytes; self.freeBytes = freeBytes
        self.swapIns = swapIns; self.swapOuts = swapOuts
    }
}

/// A measured per-app compressed-memory total: the sum of
/// CMPRS values from top(1) across the app's processes.
/// This is NOT an estimate — no proportional attribution is performed.
public struct CompressedMemoryEntry: Sendable, Equatable, Codable {
    public let appName: String
    public let bundleID: String?
    public let compressedBytes: UInt64

    public init(appName: String, bundleID: String?, compressedBytes: UInt64) {
        self.appName = appName; self.bundleID = bundleID
        self.compressedBytes = compressedBytes
    }
}

public struct BrowserTab: Sendable, Equatable, Codable {
    public let title: String
    public let url: String

    public init(title: String, url: String) {
        self.title = title; self.url = url
    }
}

/// One running browser: its open tabs plus the MEASURED total memory of the
/// browser's own processes (the sum of `ri_phys_footprint` — the same figure
/// shown in TOP APPS). We do NOT estimate per-tab memory: no browser's
/// automation API exposes it (the tab object carries only id/title/URL/loading),
/// so the section reports a real per-browser total and lists the tabs underneath.
///
/// `totalFootprintBytes` is nil when the memory cannot be honestly attributed:
/// Safari's WebKit content processes live in the system WebKit framework, are
/// shared across all WebKit apps, and only fold into the "Safari" group under
/// `--responsible-pid`. Until then their memory is not attributable to Safari.
public struct BrowserMemory: Sendable, Equatable, Codable {
    public let browser: String
    public let totalFootprintBytes: UInt64?
    public let processCount: Int
    public let tabs: [BrowserTab]

    public init(browser: String, totalFootprintBytes: UInt64?, processCount: Int, tabs: [BrowserTab]) {
        self.browser = browser; self.totalFootprintBytes = totalFootprintBytes
        self.processCount = processCount; self.tabs = tabs
    }
}

public struct MemorySnapshot: Sendable, Equatable, Codable {
    public let topApps: [AppGroup]
    public let appsStatus: SectionStatus
    public let unreadableProcessCount: Int
    public let swap: SwapInfo?
    public let compressedUsers: [CompressedMemoryEntry]
    public let compressedUnreadableCount: Int
    /// True when top(1) returned data (even if no apps had nonzero compressed memory).
    /// False when top failed entirely, so the renderer can distinguish "nothing compressed"
    /// from "could not read from top".
    public let compressedAvailable: Bool
    public let swapStatus: SectionStatus
    public let browsers: [BrowserMemory]
    public let tabsStatus: SectionStatus

    public init(topApps: [AppGroup], appsStatus: SectionStatus, unreadableProcessCount: Int,
                swap: SwapInfo?, compressedUsers: [CompressedMemoryEntry],
                compressedUnreadableCount: Int = 0, compressedAvailable: Bool = true,
                swapStatus: SectionStatus, browsers: [BrowserMemory], tabsStatus: SectionStatus) {
        self.topApps = topApps; self.appsStatus = appsStatus
        self.unreadableProcessCount = unreadableProcessCount
        self.swap = swap; self.compressedUsers = compressedUsers
        self.compressedUnreadableCount = compressedUnreadableCount
        self.compressedAvailable = compressedAvailable
        self.swapStatus = swapStatus
        self.browsers = browsers; self.tabsStatus = tabsStatus
    }
}
