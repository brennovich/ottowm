import Foundation

// One measured operation and the samples collected for it, in milliseconds.
struct Latency {
    let operation: String
    private(set) var samples: [Double] = []

    init(_ operation: String) {
        self.operation = operation
    }

    mutating func record(_ milliseconds: Double) {
        samples.append(rounded(milliseconds))
    }

    var summary: Summary {
        let sorted = samples.sorted()
        let mean = rounded(sorted.isEmpty ? 0 : sorted.reduce(0, +) / Double(sorted.count))

        return Summary(
            operation: operation,
            unit: "ms",
            count: sorted.count,
            min: sorted.first ?? 0,
            median: rounded(median(of: sorted)),
            p95: percentile(0.95, of: sorted),
            max: sorted.last ?? 0,
            mean: mean,
            perSecond: mean == 0 ? 0 : rounded(1000 / mean),
            samples: samples
        )
    }

    private func rounded(_ milliseconds: Double) -> Double {
        (milliseconds * 1000).rounded() / 1000
    }

    private func median(of sorted: [Double]) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2

        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    // Nearest rank, so every reported percentile is a sample that really happened.
    private func percentile(_ fraction: Double, of sorted: [Double]) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let rank = Int((fraction * Double(sorted.count)).rounded(.up)) - 1

        return sorted[min(max(rank, 0), sorted.count - 1)]
    }
}

// How closely the harness was watching: the mean gap between two reads of the desk is
// the resolution every number here is quoted at.
struct Sampling {
    private var polls = 0
    private var nanoseconds: UInt64 = 0

    mutating func record(_ interval: UInt64) {
        polls += 1
        nanoseconds += interval
    }

    var meanMs: Double {
        polls == 0 ? 0 : Double(nanoseconds) / Double(polls) / 1_000_000
    }
}

struct Summary: Codable {
    let operation: String
    let unit: String
    let count: Int
    let min: Double
    let median: Double
    let p95: Double
    let max: Double
    let mean: Double
    // What the mean is worth as a rate, the operations a second of nothing but this one
    // would fit.
    let perSecond: Double
    let samples: [Double]
}

// What a run is worth comparing against: the same numbers from another machine, or from
// another build on the same one, are only alike when these match.
struct Record: Codable {
    let recordedAt: String
    let version: String
    let build: String
    let commit: String
    let os: String
    let model: String
    let cpu: String
    let cores: Int
    let windows: [String]
    let iterations: Int
    let warmup: Int
    let samplingMs: Double
    let summaries: [Summary]

    var json: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        guard let data = try? encoder.encode(self) else { fail("cannot encode the record") }

        return data
    }

    var markdown: String {
        let header = ["Operation", "Samples", "min", "median", "p95", "max", "mean", "ops/s"]
        let rows = summaries.map { summary in
            [
                summary.operation,
                String(summary.count),
                milliseconds(summary.min),
                milliseconds(summary.median),
                milliseconds(summary.p95),
                milliseconds(summary.max),
                milliseconds(summary.mean),
                String(format: "%.0f", summary.perSecond),
            ]
        }
        let widths = header.indices.map { column in
            ([header] + rows).map { $0[column].count }.max() ?? 0
        }

        func line(_ cells: [String]) -> String {
            "| " + cells.enumerated()
                .map { $0.element.padding(toLength: widths[$0.offset], withPad: " ", startingAt: 0) }
                .joined(separator: " | ") + " |"
        }

        return """
        ### OttoWM \(version) (build \(build)) on \(os), \(model)

        \(line(header))
        \(line(widths.map { String(repeating: "-", count: $0) }))
        \(rows.map(line).joined(separator: "\n"))

        Milliseconds from the hotkey to the last window observed in place, on a desk of \
        \(windows.joined(separator: ", ")). \(iterations) iterations, \(warmup) discarded as warmup, \
        the frames read every \(milliseconds(samplingMs))ms on average.
        """
    }

    private func milliseconds(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
