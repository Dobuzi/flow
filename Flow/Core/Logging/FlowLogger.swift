import Foundation

enum FlowLogger {
    static func info(_ message: String) {
        print("[Flow][INFO] \(message)")
    }

    static func error(_ message: String) {
        print("[Flow][ERROR] \(message)")
    }
}
