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

    public init(pid: Int32, ppid: Int32, responsiblePID: Int32?, bundleID: String?,
                name: String, executablePath: String?, footprintBytes: UInt64,
                residentBytes: UInt64, pageIns: UInt64, isReadable: Bool) {
        self.pid = pid; self.ppid = ppid; self.responsiblePID = responsiblePID
        self.bundleID = bundleID; self.name = name; self.executablePath = executablePath
        self.footprintBytes = footprintBytes; self.residentBytes = residentBytes
        self.pageIns = pageIns; self.isReadable = isReadable
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
    public let browser: String
    public let title: String
    public let url: String
    public let estimatedBytes: UInt64?
    public let confidence: Confidence

    public init(browser: String, title: String, url: String,
                estimatedBytes: UInt64?, confidence: Confidence) {
        self.browser = browser; self.title = title; self.url = url
        self.estimatedBytes = estimatedBytes; self.confidence = confidence
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
    public let topTabs: [BrowserTab]
    public let tabsStatus: SectionStatus

    public init(topApps: [AppGroup], appsStatus: SectionStatus, unreadableProcessCount: Int,
                swap: SwapInfo?, compressedUsers: [CompressedMemoryEntry],
                compressedUnreadableCount: Int = 0, compressedAvailable: Bool = true,
                swapStatus: SectionStatus, topTabs: [BrowserTab], tabsStatus: SectionStatus) {
        self.topApps = topApps; self.appsStatus = appsStatus
        self.unreadableProcessCount = unreadableProcessCount
        self.swap = swap; self.compressedUsers = compressedUsers
        self.compressedUnreadableCount = compressedUnreadableCount
        self.compressedAvailable = compressedAvailable
        self.swapStatus = swapStatus
        self.topTabs = topTabs; self.tabsStatus = tabsStatus
    }
}
