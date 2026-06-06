/// Canonical list of supported browsers, shared by AppleScriptTabSource,
/// SnapshotBuilder, and the CLI's --browser flag.
public enum SupportedBrowsers {
    public static let all = ["Brave Browser", "Google Chrome", "Microsoft Edge", "Safari"]

    /// Case-insensitive match to a canonical display name, or nil if unsupported.
    public static func canonical(_ name: String) -> String? {
        all.first { $0.caseInsensitiveCompare(name) == .orderedSame }
    }
}
