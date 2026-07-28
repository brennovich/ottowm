import os

// Unified-logging handles, one per flow; enable verbose output at runtime with
// `log stream --level debug --predicate 'subsystem == "com.github.brennovich.ottowm"'`.
enum Log {
    private static let subsystem = "com.github.brennovich.ottowm"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    static let engine = Logger(subsystem: subsystem, category: "engine")
    static let workspaces = Logger(subsystem: subsystem, category: "workspaces")
    static let space = Logger(subsystem: subsystem, category: "space")
    static let window = Logger(subsystem: subsystem, category: "window")
    static let observer = Logger(subsystem: subsystem, category: "observer")
}
