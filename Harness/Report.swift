import Foundation

// The binary's own name, so the acceptance run and the benchmark label their output
// without either of them having to say which one it is.
let harness = ProcessInfo.processInfo.processName

let pollInterval: TimeInterval = 0.1
let placementTimeout: TimeInterval = 15

var cleanups: [() -> Void] = []

func report(_ message: String) {
    print("\(harness): \(message)")
    fflush(stdout)
}

func fail(_ message: String) -> Never {
    for cleanup in cleanups.reversed() { cleanup() }
    FileHandle.standardError.write(Data("\(harness): FAILED, \(message)\n".utf8))
    exit(EXIT_FAILURE)
}

// The probe returns nil once satisfied, or what it sees right now so an expiry says
// something more useful than "timed out".
func eventually(
    _ description: String,
    timeout: TimeInterval = placementTimeout,
    interval: TimeInterval = pollInterval,
    announce: Bool = true,
    _ probe: () -> String?
) {
    if let observed = waiting(timeout: timeout, interval: interval, probe) {
        fail("\(description), gave up after \(Int(timeout))s with \(observed)")
    }
    if announce { report("ok, \(description)") }
}

// The same wait, handing back what the probe last saw instead of ending the run, for the
// caller that has something to try when a probe goes unsatisfied.
func waiting(
    timeout: TimeInterval = placementTimeout,
    interval: TimeInterval = pollInterval,
    _ probe: () -> String?
) -> String? {
    let deadline = Date().addingTimeInterval(timeout)
    var observed: String?

    repeat {
        observed = probe()
        if observed == nil { return nil }
        // NSWorkspace tracks the frontmost application through notifications delivered to
        // the main run loop, so a probe that only sleeps reads the same stale value until
        // the deadline. Waiting on the run loop is what lets those arrive.
        RunLoop.current.run(until: Date().addingTimeInterval(interval))
    } while Date() < deadline

    return observed ?? "nothing to report"
}

func shell(_ launchPath: String, _ arguments: [String]) -> String {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice

    guard (try? process.run()) != nil else { fail("cannot run \(launchPath)") }

    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    return String(decoding: data, as: UTF8.self)
}
