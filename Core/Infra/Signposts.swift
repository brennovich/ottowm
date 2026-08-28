import os

/// Signpost intervals for Instruments, recorded by `make profile`.
///
/// The `pointsOfInterest` category is the one the Points of Interest and os_signpost
/// instruments read without being told a subsystem. An engine operation and every round
/// trip inside it become intervals on the same timeline as the time profiler's samples,
/// so a sample can be attributed to the operation that took it.
///
/// The deployment target is macOS 11.5, below the macOS 12 `OSSignposter` needs, so this
/// is the C API.
enum Signposts {
    static let log = OSLog(subsystem: Log.subsystem, category: .pointsOfInterest)

    /// Runs `body` inside a signpost interval. `detail` is dynamic, the name cannot be:
    /// `os_signpost` takes the name as a `StaticString`.
    static func interval<T>(_ name: StaticString, _ detail: @autoclosure () -> String, _ body: () -> T) -> T {
        guard log.signpostsEnabled else { return body() }

        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id, "%{public}s", detail())
        defer { os_signpost(.end, log: log, name: name, signpostID: id) }

        return body()
    }
}
