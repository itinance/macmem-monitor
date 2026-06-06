import Foundation

public struct RawTab: Sendable, Equatable {
    public let title: String
    public let url: String
    public let windowIndex: Int
    public let tabIndex: Int
    public init(title: String, url: String, windowIndex: Int, tabIndex: Int) {
        self.title = title; self.url = url
        self.windowIndex = windowIndex; self.tabIndex = tabIndex
    }
}

public protocol TabSource: Sendable {
    /// Display names of browsers currently running and inspectable.
    func runningBrowsers() -> [String]
    func tabs(for browser: String) throws -> [RawTab]
}

public struct FakeTabSource: TabSource {
    public var byBrowser: [String: [RawTab]]
    public var errorsByBrowser: [String: Error]
    public init(byBrowser: [String: [RawTab]], errorsByBrowser: [String: Error] = [:]) {
        self.byBrowser = byBrowser; self.errorsByBrowser = errorsByBrowser
    }
    public func runningBrowsers() -> [String] { byBrowser.keys.sorted() }
    public func tabs(for browser: String) throws -> [RawTab] {
        if let e = errorsByBrowser[browser] { throw e }
        return byBrowser[browser] ?? []
    }
}
