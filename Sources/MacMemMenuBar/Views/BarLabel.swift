import SwiftUI
import MacMemCore

/// Pure mapping from pressure to the collapsed bar's symbol and tint.
/// `.unknown` is neutral so the bar never shows a fabricated "all good" green.
public enum PressureStyle {
    public static func symbolName(for pressure: MemoryPressure) -> String {
        pressure == .critical ? "memorychip.fill" : "memorychip"
    }
    public static func tint(for pressure: MemoryPressure) -> Color {
        switch pressure {
        case .normal:   return .green
        case .warn:     return .yellow
        case .critical: return .red
        case .unknown:  return .secondary
        }
    }
    public static func tooltip(for pressure: MemoryPressure) -> String {
        switch pressure {
        case .normal:   return "Memory pressure: normal"
        case .warn:     return "Memory pressure: warning"
        case .critical: return "Memory pressure: critical"
        case .unknown:  return "Memory pressure unavailable"
        }
    }
}

/// The collapsed menubar label.
struct BarLabel: View {
    let pressure: MemoryPressure
    var body: some View {
        Image(systemName: PressureStyle.symbolName(for: pressure))
            .foregroundStyle(PressureStyle.tint(for: pressure))
            .help(PressureStyle.tooltip(for: pressure))
    }
}
