import Darwin
import Foundation

/// Wrapper around the PRIVATE/undocumented libsystem symbol
/// `responsibility_get_pid_responsible_for_pid`. There is NO public API for
/// this. It improves helper→app grouping but is a notarization/OS-break risk,
/// so it is DEFAULT-OFF and isolated to this one file. Disable or delete this
/// file and grouping still works via the public bundle-ID/name fallback.
///
/// The symbol is resolved at runtime via `dlsym(RTLD_DEFAULT, ...)` so a
/// missing symbol (future macOS, notarization restrictions) degrades to nil
/// rather than crashing the process at dyld load time.
public enum ResponsiblePID {
    /// C ABI function-pointer type matching the private symbol's signature.
    private typealias ResponsibilityFn = @convention(c) (pid_t) -> pid_t

    /// Lazily resolved and cached function pointer. `nil` when the symbol is
    /// absent. `static let` gives thread-safe one-time initialisation for free.
    private static let fn: ResponsibilityFn? = {
        // RTLD_DEFAULT on Darwin is UnsafeMutableRawPointer(bitPattern: -2).
        // It searches all already-loaded images; libsystem is always loaded,
        // so no dlopen/dlclose is needed.
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2),
                              "responsibility_get_pid_responsible_for_pid") else {
            return nil
        }
        return unsafeBitCast(sym, to: ResponsibilityFn.self)
    }()

    public static func lookup(for pid: pid_t, enabled: Bool) -> pid_t? {
        guard enabled else { return nil }
        guard let call = fn else { return nil }
        let result = call(pid)
        return result > 0 ? result : nil
    }
}
