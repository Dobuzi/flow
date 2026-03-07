import Foundation

enum FlowErrorScope: String {
    case dataLoad = "data_load"
    case filtering = "filtering"
    case rendering = "rendering"
    case insights = "insights"
    case settings = "settings"
}

struct FlowNonFatalError: Equatable, Identifiable {
    let scope: FlowErrorScope
    let message: String
    let debugMessage: String?

    var id: String {
        "\(scope.rawValue)|\(message)|\(debugMessage ?? "")"
    }
}

enum FlowLogger {
    enum Level: String {
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
    }

    static func info(_ message: String) {
        log(level: .info, message: message)
    }

    static func warning(_ message: String) {
        log(level: .warning, message: message)
    }

    static func error(_ message: String) {
        log(level: .error, message: message)
    }

    static func nonFatalError(
        scope: FlowErrorScope,
        userMessage: String,
        underlying error: Error? = nil
    ) -> FlowNonFatalError {
        let debug = error.map(String.init(describing:))
        var metadata: [String: String] = ["scope": scope.rawValue]
        if let debug {
            metadata["error"] = debug
        }
        log(level: .error, message: userMessage, metadata: metadata)
        return FlowNonFatalError(scope: scope, message: userMessage, debugMessage: debug)
    }

    static func log(level: Level, message: String, metadata: [String: String] = [:]) {
        let context = metadata
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")

        if context.isEmpty {
            print("[Flow][\(level.rawValue)] \(message)")
        } else {
            print("[Flow][\(level.rawValue)] \(message) | \(context)")
        }
    }
}
