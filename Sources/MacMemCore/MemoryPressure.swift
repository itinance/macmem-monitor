/// Real OS memory-pressure level, read from `kern.memorystatus_vm_pressure_level`.
/// Never inferred or faked: an unreadable/unexpected value maps to `.unknown`,
/// which the UI renders as a neutral (un-tinted) state rather than a fake "green".
public enum MemoryPressure: String, Sendable, Codable, Equatable {
    case normal, warn, critical, unknown

    /// Maps the raw sysctl level to a case. The kernel reports
    /// 1 = normal, 2 = warning, 4 = critical; anything else is unknown.
    public init(rawLevel: Int32) {
        switch rawLevel {
        case 1: self = .normal
        case 2: self = .warn
        case 4: self = .critical
        default: self = .unknown
        }
    }
}
