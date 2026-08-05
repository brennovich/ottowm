import Foundation
import os

// Times an operation and hands (operation, durationMs) to the record sink;
// formatting and level gating live in the sink.
struct Telemetry {
    private let now: () -> TimeInterval
    private let record: (String, Double) -> Void
    private let signpostLog: OSLog?

    init(
        now: @escaping () -> TimeInterval,
        record: @escaping (String, Double) -> Void,
        signpostLog: OSLog? = nil
    ) {
        self.now = now
        self.record = record
        self.signpostLog = signpostLog
    }

    func span<T>(_ operation: String, _ body: () throws -> T) rethrows -> T {
        let interval = signpostLog.map { ($0, OSSignpostID(log: $0)) }
        if let (log, id) = interval {
            os_signpost(.begin, log: log, name: "span", signpostID: id, "%{public}@", operation)
        }
        let start = now()
        defer {
            record(operation, (now() - start) * 1000)
            if let (log, id) = interval {
                os_signpost(.end, log: log, name: "span", signpostID: id)
            }
        }
        return try body()
    }
}

extension Telemetry {
    static let shared = Telemetry(
        now: { Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000 },
        record: { operation, ms in
            Log.telemetry.debug("\(operation) took \(String(format: "%.2f", ms))ms")
        },
        signpostLog: OSLog(subsystem: Log.subsystem, category: "telemetry")
    )
}
