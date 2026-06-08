import Foundation

// Temporary scaffold entry point, replaced by the SwiftUI App in a later task.
// Exists so the target compiles and the test target can link against it.
enum MacMemMenuBarBuildMarker {
    static let ok = true
}

@main
struct MacMemMenuBarMain {
    static func main() {
        _ = MacMemMenuBarBuildMarker.ok
    }
}
