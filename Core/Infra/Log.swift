import os

struct LogChannel {
    private let logger: Logger
    private var prefix = ""

    init(subsystem: String, category: String) {
        logger = Logger(subsystem: subsystem, category: category)
    }

    /// A copy whose messages start with the tag. Each display's engine and desktop log through
    /// one, so the lines of two engines can be told apart.
    func tagged(_ tag: String) -> LogChannel {
        var channel = self
        channel.prefix = "[\(tag)] "
        return channel
    }

    func debug(_ message: @autoclosure @escaping () -> String) {
        logger.debug("\(prefix + message(), privacy: .public)")
    }

    func info(_ message: @autoclosure @escaping () -> String) {
        logger.info("\(prefix + message(), privacy: .public)")
    }

    func notice(_ message: String) {
        logger.notice("\(prefix + message, privacy: .public)")
    }

    func error(_ message: String) {
        logger.error("\(prefix + message, privacy: .public)")
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
    static let state = LogChannel(subsystem: subsystem, category: "state")
    static let roundTrips = LogChannel(subsystem: subsystem, category: "roundtrips")
}
