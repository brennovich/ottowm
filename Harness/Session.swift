import AppKit

let appPath = "/Applications/OttoWM.app"
let bundleId = "com.github.brennovich.ottowm"
let safariBundleId = "com.apple.Safari"

let readyTimeout: TimeInterval = 30
let terminationTimeout: TimeInterval = 5
let tapSettleSeconds: TimeInterval = 1
let windowSettleSeconds: TimeInterval = 2

// Core/OffscreenParkingDesktop.swift parks a window 1px past the right edge, and macOS
// clamps it back by an unspecified amount. HiddenEdge.holds allows the same 10px.
let hiddenEdgeMargin: CGFloat = 10
let restoreTolerance: CGFloat = 2

// A window the run drives, and the frame it is owed whenever it is not parked.
struct Subject {
    let name: String
    let bundleId: String
    let window: AXUIElement
    let originalFrame: CGRect

    func frame() -> CGRect? {
        axFrame(of: window)
    }

    var isWhereItWas: Bool {
        guard let frame = frame() else { return false }

        return abs(frame.minX - originalFrame.minX) <= restoreTolerance
            && abs(frame.minY - originalFrame.minY) <= restoreTolerance
    }

    // The hotkeys act on the focused window, and a workspace switch hands the focus to
    // whichever window it pleases, so whoever wants this one moved says so first.
    func focus() {
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first?.activate()

        eventually("\(name) is focused", announce: false) { lacksFocus() }
    }

    // Whether this window has the focus right now, for a loop that polls without running
    // the main run loop and so cannot use lacksFocus below.
    var hasFocus: Bool {
        systemFocusedWindow().map { CFEqual($0, window) } ?? false
    }

    // Nil when this window is the one a hotkey would act on, otherwise where the focus
    // actually is. Asked for the way OttoWM asks in Core/AXWindow.focused(), the focused
    // window of the frontmost application.
    func lacksFocus() -> String? {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return "nothing is frontmost" }
        guard frontmost.bundleIdentifier == bundleId else {
            return "frontmost is \(frontmost.localizedName ?? "an unnamed application")"
        }
        guard let focused = attribute(
            AXUIElementCreateApplication(frontmost.processIdentifier), kAXFocusedWindowAttribute
        ), CFEqual(focused, window) else {
            return "\(name) is frontmost with another of its windows focused"
        }
        return nil
    }
}

// Drives the installed OttoWM.app the way a user does: real hotkeys through the event
// tap, real windows read back through the accessibility API. Nothing here imports the
// app's own code on purpose, the bundle under test is the one shipped in the release zip.
//
// The desk it sets up is a plausible one, a file browser, a terminal, a browser and an
// editor, because a workspace switch costs what the windows standing on it cost.
struct Session {
    let ottowm: Process
    // The window the hotkeys move between workspaces.
    let movable: Subject
    // The ones that only ever move because the workspace they stand on was left.
    let others: [Subject]

    private let hiddenEdgeX: CGFloat

    var subjects: [Subject] { others + [movable] }

    // Every instance is a whole desk of its own, so a run at two costs what a run at one
    // costs twice over, and the difference between them is what a window is worth.
    //
    // An arranged desk stands in the four quarters of the screen instead of wherever
    // macOS put it, for a run that asserts which window a focus move lands on and has to
    // know the geometry to do it.
    static func start(instances: Int = 1, arranged: Bool = false) -> Session {
        guard AXIsProcessTrusted() else {
            fail("""
            the harness itself has no Accessibility permission, it cannot post events nor read \
            window frames. Grant it to the terminal running make, or on CI to the process running \
            the \(harness) binary.
            """)
        }

        guard FileManager.default.fileExists(atPath: appPath) else {
            fail("no app at \(appPath), run `make install` first")
        }

        guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty else {
            fail("another OttoWM is already running, it would race this one for the same hotkeys, quit it first")
        }

        let sources = stageDesk(instances: instances)
        let ottowm = launchOttoWM()

        // Each window is claimed as it is found, because two instances of the same desk put
        // two windows of the same application on screen and the second must not answer to
        // the first one's title.
        var claimed: [AXUIElement] = []
        let windows = sources.map { source -> (String, String, AXUIElement) in
            let window = openWindow(source, claimed: claimed)
            claimed.append(window)

            return (source.name, source.bundleId, window)
        }

        if arranged { arrange(windows) }

        // Everything is up, nothing else is about to move on its own, so what the windows
        // read now is what they are owed back after every switch.
        Thread.sleep(forTimeInterval: windowSettleSeconds)

        let hiddenEdgeX = CGDisplayBounds(CGMainDisplayID()).maxX - 1
        let subjects = windows.map { name, bundleId, window -> Subject in
            guard let frame = axFrame(of: window) else { fail("cannot read the \(name) window frame") }

            report("\(name) at \(frame)")

            guard frame.minX < hiddenEdgeX - hiddenEdgeMargin else {
                fail("the \(name) window already sits at the hidden edge, parking it would prove nothing")
            }

            return Subject(name: name, bundleId: bundleId, window: window, originalFrame: frame)
        }

        report("hidden edge at x=\(hiddenEdgeX)")

        guard let movable = subjects.last else { fail("no window to drive") }

        let session = Session(
            ottowm: ottowm,
            movable: movable,
            others: subjects.dropLast(),
            hiddenEdgeX: hiddenEdgeX
        )
        session.movable.focus()

        return session
    }

    // The subject opened in the named application, for a scene that drives one of the
    // standing windows rather than the movable one.
    func subject(named name: String) -> Subject {
        guard let subject = subjects.first(where: { $0.name == name }) else {
            fail("no subject named \(name)")
        }
        return subject
    }

    // Waits for the focus a hotkey was asked to move, and says where it actually is when
    // it gives up.
    func expectFocused(_ subject: Subject) {
        eventually("the \(subject.name) window took the focus") { subject.lacksFocus() }
    }

    // Where every window stands right now, for a wait that gives up without one.
    var standing: String {
        subjects
            .map { "\($0.name) \(isParked($0) ? "parked" : "at \($0.frame().map { "\($0.origin)" } ?? "nowhere")")" }
            .joined(separator: ", ")
    }

    func isParked(_ subject: Subject) -> Bool {
        guard let frame = subject.frame() else { return false }

        return frame.minX >= hiddenEdgeX - hiddenEdgeMargin
    }

    // Waits for every subject to satisfy the expectation, and says which ones do not and
    // where they stand when it gives up.
    func expect(_ description: String, _ subjects: [Subject], _ satisfies: (Subject) -> Bool) {
        eventually(description) {
            let pending = subjects.filter { !satisfies($0) }
            guard !pending.isEmpty else { return nil }

            return pending
                .map { "\($0.name) at \($0.frame().map { "\($0)" } ?? "nowhere")" }
                .joined(separator: ", ")
        }
    }

    // Adds a binding to the staged configuration, for a run that asks OttoWM to reload it
    // and then posts the key it names. Appended rather than written over: the run still
    // needs the quit and restart bindings the staged defaults carry.
    func rebind(_ line: String) {
        guard let staged = try? String(contentsOf: stagedConfig, encoding: .utf8) else {
            fail("cannot read the staged configuration at \(stagedConfig.path)")
        }

        write(staged + "\n\(line)\n", to: stagedConfig)
    }

    // A reload builds a new event tap, and a hotkey posted before it is up is lost.
    func waitForReload() {
        eventually("OttoWM reloaded its config") { [ottowm] in
            ottowmLog(of: ottowm.processIdentifier).contains("config reloaded")
                ? nil
                : "no reload line logged yet"
        }

        Thread.sleep(forTimeInterval: tapSettleSeconds)
    }

    // The desk OttoWM took over is owed back whole when it goes.
    func waitForExit() {
        eventually("OttoWM exited") { [ottowm] in
            ottowm.isRunning ? "still running" : nil
        }
    }

    func finish() {
        for cleanup in cleanups.reversed() { cleanup() }
        cleanups = []
    }
}

private func launchOttoWM() -> Process {
    let ottowm = Process()
    ottowm.executableURL = URL(fileURLWithPath: "\(appPath)/Contents/MacOS/OttoWM")
    ottowm.environment = ProcessInfo.processInfo.environment.merging(
        ["XDG_CONFIG_HOME": temporaryDirectory.path]
    ) { _, staged in staged }

    guard (try? ottowm.run()) != nil else { fail("cannot launch \(ottowm.executableURL!.path)") }

    // Waited out rather than merely asked to quit, and killed if it will not: the next
    // harness run refuses to start while an OttoWM is up, and CI runs them back to back.
    // A SIGTERM landing while the app is still working through the last events it was
    // sent is one AppKit takes its time with.
    cleanups.append {
        guard ottowm.isRunning else { return }

        ottowm.terminate()
        let deadline = Date().addingTimeInterval(terminationTimeout)
        while ottowm.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        guard ottowm.isRunning else { return }

        report("OttoWM pid=\(ottowm.processIdentifier) ignored SIGTERM for \(Int(terminationTimeout))s, killing it")
        kill(ottowm.processIdentifier, SIGKILL)
        ottowm.waitUntilExit()
    }

    report("launched OttoWM pid=\(ottowm.processIdentifier)")

    eventually("OttoWM is up", timeout: readyTimeout, interval: 0.5) {
        guard ottowm.isRunning else { fail("OttoWM exited with status \(ottowm.terminationStatus)") }

        let log = ottowmLog(of: ottowm.processIdentifier)

        if log.contains("accessibility permission missing") {
            fail("OttoWM has no Accessibility permission, grant it to \(appPath)")
        }
        if log.contains("event tap creation failed") {
            fail("OttoWM could not create its event tap, no hotkey will ever reach it")
        }
        return log.contains("launched") ? nil : "no launch line logged yet"
    }

    // The launch line is logged a few statements before the event tap is created, and a
    // hotkey posted in between is simply lost.
    Thread.sleep(forTimeInterval: tapSettleSeconds)

    return ottowm
}

private func ottowmLog(of pid: pid_t) -> String {
    shell("/usr/bin/log", [
        "show", "--style", "compact", "--last", "5m", "--info", "--debug",
        "--predicate", "subsystem == \"\(bundleId)\" AND processIdentifier == \(pid)",
    ])
}
