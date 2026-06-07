import Foundation

/// Reads per-process compressed memory from macOS `top` (the CMPRS column).
/// `top` is Apple-entitled to read every process's memory WITHOUT root, which
/// `task_for_pid` is not — so this works for normal users and catches the real
/// swap-driving apps (browsers, container runtimes). This is measured data.
public struct TopCompressedSource {
    public init() {}

    public func compressedByPID() -> [pid_t: UInt64] {
        guard let output = Self.runTop() else { return [:] }
        return Self.parse(output)
    }

    /// Parses `top -l 1 -stats pid,cmprs` output into pid → compressed bytes.
    /// Skips the summary header block; begins at the "PID" column-header line.
    static func parse(_ output: String) -> [pid_t: UInt64] {
        var result: [pid_t: UInt64] = [:]
        var inTable = false
        for raw in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if !inTable {
                if line.hasPrefix("PID") { inTable = true }
                continue
            }
            let cols = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init).filter { !$0.isEmpty }
            guard cols.count >= 2, let pid = pid_t(cols[0]), let bytes = parseSize(cols[1]) else { continue }
            result[pid] = bytes
        }
        return result
    }

    /// Parses a top size token ("0B","4816K","102M","18G","2.5G","790T", or bare digits) into bytes (1024-based).
    static func parseSize(_ s: String) -> UInt64? {
        guard let last = s.last else { return nil }
        let mult: [Character: Double] = ["B": 1, "K": 1024, "M": 1_048_576,
                                         "G": 1_073_741_824, "T": 1_099_511_627_776]
        if let m = mult[last] {
            guard let n = Double(s.dropLast()) else { return nil }
            return UInt64((n * m).rounded())
        }
        if let n = UInt64(s) { return n }
        if let d = Double(s) { return UInt64(d.rounded()) }
        return nil
    }

    private static func runTop() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/top")
        p.arguments = ["-l", "1", "-stats", "pid,cmprs"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()  // read before wait to avoid deadlock
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
