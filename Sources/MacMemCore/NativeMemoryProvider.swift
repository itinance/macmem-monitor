import Foundation
import AppKit
import Darwin

public struct NativeMemoryProvider: MemoryProvider {
    public init() {}

    // MARK: Processes

    public func listProcesses() throws -> [ProcessSample] {
        let pids = try allPIDs()
        let appIdentity = Self.appIdentityByPID()   // bundleID + name for GUI apps

        return pids.compactMap { pid -> ProcessSample? in
            guard pid > 0 else { return nil }
            let path = Self.path(for: pid)
            let parentPID = Self.ppid(for: pid)
            let name = appIdentity[pid]?.name ?? Self.name(for: pid, fallbackPath: path)
            let bundleID = appIdentity[pid]?.bundleID ?? Self.bundleID(forPath: path)

            if let usage = Self.rusage(for: pid) {
                return ProcessSample(pid: pid, ppid: parentPID, responsiblePID: nil,
                                     bundleID: bundleID, name: name, executablePath: path,
                                     footprintBytes: usage.footprint, residentBytes: usage.resident,
                                     pageIns: usage.pageIns, isReadable: true)
            } else {
                // Not owned by us / not permitted: still list it, marked unreadable.
                return ProcessSample(pid: pid, ppid: parentPID, responsiblePID: nil,
                                     bundleID: bundleID, name: name, executablePath: path,
                                     footprintBytes: 0, residentBytes: 0, pageIns: 0, isReadable: false)
            }
        }
    }

    private func allPIDs() throws -> [pid_t] {
        let needed = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard needed > 0 else { throw NativeError.procListFailed }
        let count = Int(needed) / MemoryLayout<pid_t>.size
        var buffer = [pid_t](repeating: 0, count: count)
        let written = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &buffer, needed)
        guard written > 0 else { throw NativeError.procListFailed }
        let actual = Int(written) / MemoryLayout<pid_t>.size
        return Array(buffer.prefix(actual)).filter { $0 != 0 }
    }

    private static func rusage(for pid: pid_t) -> (footprint: UInt64, resident: UInt64, pageIns: UInt64)? {
        var info = rusage_info_v2()
        let rc = withUnsafeMutablePointer(to: &info) { ptr -> Int32 in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { reboundPtr in
                proc_pid_rusage(pid, RUSAGE_INFO_V2, reboundPtr)
            }
        }
        guard rc == 0 else { return nil }
        return (info.ri_phys_footprint, info.ri_resident_size, info.ri_pageins)
    }

    private static func ppid(for pid: pid_t) -> Int32 {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let rc = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
        guard rc == size else { return 0 }
        return Int32(info.pbi_ppid)
    }

    // PROC_PIDPATHINFO_MAXSIZE is defined as 4*MAXPATHLEN in proc_info.h but the
    // compound-expression macro is not importable by the Swift overlay on macOS 26.
    // MAXPATHLEN == 1024, so 4*1024 = 4096.
    private static let pidPathInfoMaxSize: Int = 4 * Int(MAXPATHLEN)

    private static func path(for pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: pidPathInfoMaxSize)
        let rc = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return rc > 0 ? String(cString: buffer) : nil
    }

    private static func name(for pid: pid_t, fallbackPath: String?) -> String {
        var buffer = [CChar](repeating: 0, count: Int(2 * MAXCOMLEN))
        let rc = proc_name(pid, &buffer, UInt32(buffer.count))
        if rc > 0 { return String(cString: buffer) }
        if let p = fallbackPath { return (p as NSString).lastPathComponent }
        return "pid \(pid)"
    }

    private static func bundleID(forPath path: String?) -> String? {
        guard let path else { return nil }
        // Walk up to the enclosing .app, read its Info.plist bundle id.
        var url = URL(fileURLWithPath: path)
        while url.pathComponents.count > 1 {
            if url.pathExtension == "app" {
                return Bundle(url: url)?.bundleIdentifier
            }
            url.deleteLastPathComponent()
        }
        return nil
    }

    /// Map of pid → (bundleID, localizedName) for GUI applications via NSWorkspace.
    /// NSWorkspace is main-thread-affined, so hop to main when called off-main.
    /// Interim approach — migrate to @MainActor isolation once the protocol and
    /// callers support async/actor contexts.
    private static func appIdentityByPID() -> [pid_t: (bundleID: String?, name: String)] {
        if Thread.isMainThread {
            return collectAppIdentity()
        } else {
            return DispatchQueue.main.sync { collectAppIdentity() }
        }
    }

    private static func collectAppIdentity() -> [pid_t: (bundleID: String?, name: String)] {
        var map: [pid_t: (String?, String)] = [:]
        for app in NSWorkspace.shared.runningApplications {
            let pid = app.processIdentifier
            guard pid > 0 else { continue }
            map[pid] = (app.bundleIdentifier, app.localizedName ?? "pid \(pid)")
        }
        return map
    }

    // MARK: Swap

    public func readSwap() throws -> SwapInfo {
        let usage = try Self.swapUsage()
        let (ins, outs) = Self.swapInOut()
        return SwapInfo(totalBytes: usage.total, usedBytes: usage.used,
                        freeBytes: usage.avail, swapIns: ins, swapOuts: outs)
    }

    private static func swapUsage() throws -> (total: UInt64, used: UInt64, avail: UInt64) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        var mib = [CTL_VM, VM_SWAPUSAGE]
        let rc = sysctl(&mib, 2, &usage, &size, nil, 0)
        guard rc == 0 else { throw NativeError.sysctlFailed }
        return (usage.xsu_total, usage.xsu_used, usage.xsu_avail)
    }

    private static func swapInOut() -> (ins: UInt64, outs: UInt64) {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let rc = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }
        guard rc == KERN_SUCCESS else { return (0, 0) }
        return (UInt64(stats.swapins), UInt64(stats.swapouts))
    }
}

enum NativeError: Error {
    case procListFailed
    case sysctlFailed
}
