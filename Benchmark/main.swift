import AppKit

// Measures what a hotkey costs the user: the wall time from posting it to seeing the
// window where the action promised to put it. Same harness the acceptance run drives,
// same installed bundle, so a number here is a number about the shipped app.

let samplingInterval: useconds_t = 1000
let settleSeconds: TimeInterval = 0.3

struct Options {
    var iterations = 30
    var warmup = 2
    var output = "build/benchmark.json"
    var summary = ProcessInfo.processInfo.environment["GITHUB_STEP_SUMMARY"]
    var budgetP95: Double?
}

func parseOptions() -> Options {
    var options = Options()
    var arguments = CommandLine.arguments.dropFirst().makeIterator()

    func next(_ flag: String) -> String {
        guard let value = arguments.next() else { fail("\(flag) needs a value") }
        return value
    }

    func number(_ flag: String) -> Double {
        guard let value = Double(next(flag)), value >= 0 else { fail("\(flag) needs a number") }
        return value
    }

    while let argument = arguments.next() {
        switch argument {
        case "--iterations": options.iterations = Int(number(argument))
        case "--warmup": options.warmup = Int(number(argument))
        case "--output": options.output = next(argument)
        case "--summary": options.summary = next(argument)
        case "--budget-p95": options.budgetP95 = number(argument)
        default:
            fail("unknown argument \(argument), usage: benchmark "
                + "[--iterations N] [--warmup N] [--output PATH] [--summary PATH] [--budget-p95 MS]")
        }
    }

    guard options.iterations > 0 else { fail("--iterations needs at least one iteration") }

    return options
}

func trimmed(_ output: String) -> String {
    output.trimmingCharacters(in: .whitespacesAndNewlines)
}

func installedApp() -> (version: String, build: String) {
    guard let info = Bundle(path: appPath)?.infoDictionary,
          let version = info["CFBundleShortVersionString"] as? String,
          let build = info["CFBundleVersion"] as? String
    else { fail("cannot read the version of \(appPath)") }

    return (version, build)
}

func operatingSystem() -> String {
    let version = ProcessInfo.processInfo.operatingSystemVersion

    return "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
}

func commit() -> String {
    if let sha = ProcessInfo.processInfo.environment["GITHUB_SHA"] { return sha }
    let sha = trimmed(shell("/usr/bin/git", ["rev-parse", "HEAD"]))

    return sha.isEmpty ? "unknown" : sha
}

func sysctl(_ key: String) -> String {
    trimmed(shell("/usr/sbin/sysctl", ["-n", key]))
}

func write(_ data: Data, to path: String) {
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    guard (try? data.write(to: url)) != nil else { fail("cannot write \(path)") }
}

// The GitHub step summary is a file every step adds to, never one a step owns.
func append(_ text: String, to path: String) {
    guard FileManager.default.fileExists(atPath: path),
          let handle = FileHandle(forWritingAtPath: path)
    else { return write(Data("\(text)\n".utf8), to: path) }

    handle.seekToEndOfFile()
    handle.write(Data("\n\(text)\n".utf8))
    handle.closeFile()
}

let options = parseOptions()
let session = Session.start()

var sampling = Sampling()

// Returns the milliseconds between the hotkey going out and the first read of the desk
// that shows it settled. The clock is read before that read, so what stands between the
// number and the truth is how long a read of every window takes.
func measure(_ description: String, _ trigger: () -> Void, until settled: () -> Bool) -> Double {
    Thread.sleep(forTimeInterval: settleSeconds)

    guard !settled() else { fail("\(description) already, the hotkey would measure nothing") }

    let start = DispatchTime.now().uptimeNanoseconds
    trigger()

    var previous = start
    while true {
        let now = DispatchTime.now().uptimeNanoseconds
        sampling.record(now - previous)
        previous = now

        if settled() { return Double(now - start) / 1_000_000 }

        guard Double(now - start) < placementTimeout * 1_000_000_000 else {
            fail("\(description) did not happen within \(Int(placementTimeout))s")
        }
        usleep(samplingInterval)
    }
}

func movedAway() -> Bool {
    session.isParked(session.movable)
}

// The switch is done when the workspace being entered is on screen and the one being
// left is out of the way, whichever of the two the desktop gets to last.
func swapped() -> Bool {
    session.movable.isWhereItWas && session.others.allSatisfy(session.isParked)
}

func deskIsBack() -> Bool {
    session.subjects.allSatisfy { $0.isWhereItWas }
}

var move = Latency("move-window-to-workspace")
var switchTo = Latency("switch-to-workspace")

report("measuring \(options.iterations) iterations after \(options.warmup) warmup ones")

for iteration in 1...(options.warmup + options.iterations) {
    session.movable.focus()

    let moved = measure("the moved window parked", { moveWindowToWorkspace(2) }, until: movedAway)
    let switched = measure("the desk swapped", { switchToWorkspace(2) }, until: swapped)

    // Workspace 1 gets its desk back, untimed: the return leg starts from a different
    // state than the two above and its numbers would only blur theirs.
    session.movable.focus()
    _ = measure("the moved window parked", { moveWindowToWorkspace(1) }, until: movedAway)
    _ = measure("the desk came back", { switchToWorkspace(1) }, until: deskIsBack)

    guard iteration > options.warmup else { continue }

    move.record(moved)
    switchTo.record(switched)

    report("iteration \(iteration - options.warmup)/\(options.iterations)")
}

session.finish()

let app = installedApp()
let record = Record(
    recordedAt: ISO8601DateFormatter().string(from: Date()),
    version: app.version,
    build: app.build,
    commit: commit(),
    os: operatingSystem(),
    model: sysctl("hw.model"),
    cpu: sysctl("machdep.cpu.brand_string"),
    cores: ProcessInfo.processInfo.activeProcessorCount,
    windows: session.subjects.map { $0.name },
    iterations: options.iterations,
    warmup: options.warmup,
    samplingMs: sampling.meanMs,
    summaries: [move.summary, switchTo.summary]
)

write(record.json, to: options.output)
if let summary = options.summary { append(record.markdown, to: summary) }

print(record.markdown)
report("recorded \(options.output)")

if let budget = options.budgetP95 {
    let overBudget = record.summaries.filter { $0.p95 > budget }
    guard overBudget.isEmpty else {
        fail(overBudget
            .map { "\($0.operation) p95 \(String(format: "%.1f", $0.p95))ms over the \(Int(budget))ms budget" }
            .joined(separator: ", "))
    }
}

report("PASSED")
