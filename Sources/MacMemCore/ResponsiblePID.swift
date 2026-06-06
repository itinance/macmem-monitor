import Foundation

/// Wrapper around the PRIVATE/undocumented libsystem symbol
/// `responsibility_get_pid_responsible_for_pid`. There is NO public API for
/// this. It improves helper→app grouping but is a notarization/OS-break risk,
/// so it is DEFAULT-OFF and isolated to this one file. Disable or delete this
/// file and grouping still works via the public bundle-ID/name fallback.
@_silgen_name("responsibility_get_pid_responsible_for_pid")
private func responsibility_get_pid_responsible_for_pid(_ pid: pid_t) -> pid_t

public enum ResponsiblePID {
    public static func lookup(for pid: pid_t, enabled: Bool) -> pid_t? {
        guard enabled else { return nil }
        let result = responsibility_get_pid_responsible_for_pid(pid)
        return result > 0 ? result : nil
    }
}
