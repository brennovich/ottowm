import os

struct LogChannel {
    private let logger: Logger

    init(subsystem: String, category: String) {
        logger = Logger(subsystem: subsystem, category: category)
    }

    func debug(_ message: @autoclosure @escaping () -> String) {
        logger.debug("\(message(), privacy: .public)")
    }

    func info(_ message: @autoclosure @escaping () -> String) {
        logger.info("\(message(), privacy: .public)")
    }

    func notice(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }

    func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}

enum Log {
    static let subsystem = "com.github.brennovich.ottowm"

    static let app = LogChannel(subsystem: subsystem, category: "app")
    static let config = LogChannel(subsystem: subsystem, category: "config")
    static let hotkey = LogChannel(subsystem: subsystem, category: "hotkey")
    static let engine = LogChannel(subsystem: subsystem, category: "engine")
    static let desktop = LogChannel(subsystem: subsystem, category: "desktop")
    static let window = LogChannel(subsystem: subsystem, category: "window")
    static let windows = LogChannel(subsystem: subsystem, category: "windows")
    static let observer = LogChannel(subsystem: subsystem, category: "observer")
    static let roundTrips = LogChannel(subsystem: subsystem, category: "roundtrips")
}
