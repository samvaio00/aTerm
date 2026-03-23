import Foundation
import os.log

/// Centralized logger for aTerm. Writes to both os_log (visible in Console.app) and stderr.
enum Log {
    private static let subsystem = "com.aterm.app"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let pty = Logger(subsystem: subsystem, category: "pty")
    static let window = Logger(subsystem: subsystem, category: "window")
    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let mcp = Logger(subsystem: subsystem, category: "mcp")

    /// Also print to stderr for terminal visibility when launched from CLI
    static func debug(_ category: String, _ message: String) {
        let line = "[\(category)] \(message)"
        fputs(line + "\n", stderr)
        Logger(subsystem: subsystem, category: category).debug("\(message)")
    }

    static func error(_ category: String, _ message: String) {
        let line = "[ERROR][\(category)] \(message)"
        fputs(line + "\n", stderr)
        Logger(subsystem: subsystem, category: category).error("\(message)")
    }
}
