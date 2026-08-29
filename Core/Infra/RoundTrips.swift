import Foundation

/// Models an end-to-end call out of the process, identified by kind and subject: `read AXPosition`,
/// `action AXRaise`, `read CGWindowList`. Calls sharing both are the same
/// round trip and are counted together.
struct RoundTrip: Hashable {
    enum Kind: String {
        case read
        case write
        case action
        case subscribe
    }

    let kind: Kind
    let subject: String

    var description: String { "\(kind.rawValue) \(subject)" }
}

/// What one call cost an operation: how many round trips it made, and how long they took.
struct RoundTripCost {
    let roundTrip: RoundTrip
    let count: Int
    let nanoseconds: UInt64

    var milliseconds: Double { Double(nanoseconds) / 1_000_000 }
}

/// What one engine operation spent leaving the process.
struct OperationCost {
    let operation: String
    /// How long the whole operation took. Here as the denominator the round trip time is
    /// read against, not as a latency of its own: the benchmark measures those from
    /// outside, on the shipped bundle and with the window actually on screen.
    let nanoseconds: UInt64
    /// Most expensive call first.
    let calls: [RoundTripCost]

    var count: Int { calls.reduce(0) { $0 + $1.count } }
    var roundTripNanoseconds: UInt64 { calls.reduce(0) { $0 + $1.nanoseconds } }
    var milliseconds: Double { Double(nanoseconds) / 1_000_000 }
    var roundTripMilliseconds: Double { Double(roundTripNanoseconds) / 1_000_000 }

    var summary: String {
        let breakdown = calls
            .map { "\($0.roundTrip.description) x\($0.count) \(format($0.milliseconds))" }
            .joined(separator: ", ")

        return "\(operation) \(format(milliseconds)), "
            + "\(count) round trips \(format(roundTripMilliseconds)): \(breakdown)"
    }

    private func format(_ milliseconds: Double) -> String {
        String(format: "%.2fms", milliseconds)
    }
}

/// Prices an engine operation in the calls it makes out of the process.
///
/// Almost all of an operation is the main thread blocked waiting for another process to
/// answer, where a sampling profiler sees a stalled thread rather than the question it
/// asked. Counting at the boundary names the question instead, and the count is exact
/// rather than sampled. That count is the one thing about an operation the benchmark
/// cannot see from outside, which is why it is the only part broken down here.
///
/// An operation that fans its calls out over several threads records from all of them, so
/// every access to the counters is taken under `lock`. The operation itself belongs to the
/// thread that opened it: a `duringOperation` entered on another thread while one is in
/// flight counts into it rather than replacing it.
final class RoundTrips {
    static let shared = RoundTrips { Log.roundTrips.debug($0.summary) }

    private let report: (OperationCost) -> Void
    private let lock = NSLock()
    private var counts: [RoundTrip: Int] = [:]
    private var nanoseconds: [RoundTrip: UInt64] = [:]
    private var order: [RoundTrip] = []
    private var owner: Thread?
    private var depth = 0
    private var startedAt: UInt64 = 0

    init(report: @escaping (OperationCost) -> Void) {
        self.report = report
    }

    /// Runs `body` as one operation, and reports what it spent when the outermost one
    /// ends. A nested operation joins the one around it: they are one unit of engine work
    /// and share the reads `OperationCache` holds.
    func duringOperation<T>(_ operation: StaticString, _ body: () -> T) -> T {
        Signposts.interval("operation", "\(operation)") {
            begin()
            defer { end(operation) }

            return body()
        }
    }

    /// Runs `body` as one round trip, timing it and counting it against `subject`.
    func measure<T>(_ kind: RoundTrip.Kind, _ subject: String, _ body: () -> T) -> T {
        Signposts.interval("round trip", "\(kind.rawValue) \(subject)") {
            let start = DispatchTime.now().uptimeNanoseconds
            let result = body()
            record(
                RoundTrip(kind: kind, subject: subject),
                nanoseconds: DispatchTime.now().uptimeNanoseconds - start
            )

            return result
        }
    }

    func record(_ roundTrip: RoundTrip, nanoseconds elapsed: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        guard depth > 0 else { return }

        if counts[roundTrip] == nil { order.append(roundTrip) }
        counts[roundTrip, default: 0] += 1
        nanoseconds[roundTrip, default: 0] += elapsed
    }

    private func begin() {
        lock.lock()
        defer { lock.unlock() }

        guard let owner else {
            owner = Thread.current
            depth = 1
            clear()
            startedAt = DispatchTime.now().uptimeNanoseconds
            return
        }
        if owner === Thread.current { depth += 1 }
    }

    /// Reported outside the lock: `report` logs, and the counters are free for the next
    /// operation as soon as they have been read.
    private func end(_ operation: StaticString) {
        guard let cost = finish(operation) else { return }

        report(cost)
    }

    private func finish(_ operation: StaticString) -> OperationCost? {
        lock.lock()
        defer { lock.unlock() }

        guard owner === Thread.current else { return nil }

        depth -= 1
        guard depth == 0 else { return nil }
        owner = nil
        guard !order.isEmpty else { return nil }

        let calls = order
            .map { RoundTripCost(roundTrip: $0, count: counts[$0] ?? 0, nanoseconds: nanoseconds[$0] ?? 0) }
            .sorted { $0.nanoseconds > $1.nanoseconds }
        let elapsed = DispatchTime.now().uptimeNanoseconds - startedAt
        clear()

        return OperationCost(operation: "\(operation)", nanoseconds: elapsed, calls: calls)
    }

    private func clear() {
        counts.removeAll(keepingCapacity: true)
        nanoseconds.removeAll(keepingCapacity: true)
        order.removeAll(keepingCapacity: true)
    }
}
