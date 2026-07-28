import os

// Logs a plain message as a single public string — this is a personal,
// non-sandboxed agent where redacted logs would be useless. The isEnabled guard
// keeps messages for disabled levels unevaluated.
struct LogChannel {
    private let logger: Logger
    private let log: OSLog

    init(subsystem: String, category: String) {
        logger = Logger(subsystem: subsystem, category: category)
        log = OSLog(subsystem: subsystem, category: category)
    }

    func debug(_ message: @autoclosure () -> String) {
        guard log.isEnabled(type: .debug) else { return }
        let evaluated = message()
        logger.debug("\(evaluated, privacy: .public)")
    }

    func info(_ message: @autoclosure () -> String) {
        guard log.isEnabled(type: .info) else { return }
        let evaluated = message()
        logger.info("\(evaluated, privacy: .public)")
    }

    func notice(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }

    func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}

// Unified-logging handles, one per flow; enable verbose output at runtime with
// `log stream --level debug --predicate 'subsystem == "com.github.brennovich.ottowm"'`.
enum Log {
    static let subsystem = "com.github.brennovich.ottowm"

    static let app = LogChannel(subsystem: subsystem, category: "app")
    static let hotkey = LogChannel(subsystem: subsystem, category: "hotkey")
    static let engine = LogChannel(subsystem: subsystem, category: "engine")
    static let space = LogChannel(subsystem: subsystem, category: "space")
    static let window = LogChannel(subsystem: subsystem, category: "window")
    static let observer = LogChannel(subsystem: subsystem, category: "observer")
    static let telemetry = LogChannel(subsystem: subsystem, category: "telemetry")
}
