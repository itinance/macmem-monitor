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

public struct SwapCulprit: Sendable, Equatable, Codable {
    public let appName: String
    public let bundleID: String?
    public let score: Double
    public let confidence: Confidence

    public init(appName: String, bundleID: String?, score: Double, confidence: Confidence) {
        self.appName = appName; self.bundleID = bundleID
        self.score = score; self.confidence = confidence
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
    public let swapCulprits: [SwapCulprit]
    public let swapStatus: SectionStatus
    public let topTabs: [BrowserTab]
    public let tabsStatus: SectionStatus

    public init(topApps: [AppGroup], appsStatus: SectionStatus, unreadableProcessCount: Int,
                swap: SwapInfo?, swapCulprits: [SwapCulprit], swapStatus: SectionStatus,
                topTabs: [BrowserTab], tabsStatus: SectionStatus) {
        self.topApps = topApps; self.appsStatus = appsStatus
        self.unreadableProcessCount = unreadableProcessCount
        self.swap = swap; self.swapCulprits = swapCulprits; self.swapStatus = swapStatus
        self.topTabs = topTabs; self.tabsStatus = tabsStatus
    }
}
