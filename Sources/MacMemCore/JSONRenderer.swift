import Foundation

public enum JSONRenderer {
    public static func render(_ snap: MemorySnapshot) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snap)
        return String(decoding: data, as: UTF8.self)
    }
}
