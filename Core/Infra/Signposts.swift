import os

enum Signposts {
    static let log = OSLog(subsystem: Log.subsystem, category: .pointsOfInterest)

    static func interval<T>(_ name: StaticString, _ detail: @autoclosure () -> String, _ body: () -> T) -> T {
        guard log.signpostsEnabled else { return body() }

        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id, "%{public}s", detail())
        defer { os_signpost(.end, log: log, name: name, signpostID: id) }

        return body()
    }
}
