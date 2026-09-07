import AppKit

let appPath = "/Applications/OttoWM.app"
let bundleId = "com.github.brennovich.ottowm"
let safariBundleId = "com.apple.Safari"
let terminalBundleId = "com.apple.Terminal"

let readyTimeout: TimeInterval = 30
let terminationTimeout: TimeInterval = 5
let tapSettleSeconds: TimeInterval = 1
let windowSettleSeconds: TimeInterval = 2

// Core/OffscreenParkingDesktop.swift parks a window 1px past the right edge, and macOS
// clamps it back by an unspecified amount. HiddenEdge.holds allows the same 10px.
let hiddenEdgeMargin: CGFloat = 10
let restoreTolerance: CGFloat = 2

// A window the run drives, and the frame it was read at, which it goes back to whenever it
// is not parked.
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

    // Whether the window is at a frame, the size included, for a scene that asserts a
    // maximize or a fill: isWhereItWas reads the origin alone, which a window still filling
    // the screen satisfies as well as one put back.
    //
    // The size is allowed more room than the origin because an application takes the
    // position it is handed but rounds the size to one it can take.
    func stands(at target: CGRect, sizedWithin sizeTolerance: CGFloat = restoreTolerance) -> Bool {
        guard let frame = frame() else { return false }

        return abs(frame.minX - target.minX) <= restoreTolerance
            && abs(frame.minY - target.minY) <= restoreTolerance
            && abs(frame.width - target.width) <= sizeTolerance
            && abs(frame.height - target.height) <= sizeTolerance
    }

    // The frame it was read at, the size included.
    var isAsItWas: Bool {
        stands(at: originalFrame, sizedWithin: refitTolerance)
    }

    // Brings this window's tab to the front, so what a check reads next is the frame the
    // window is at rather than the one it had when the tab was last in front. A window that
    // is not a tab is already the one its application lists.
    func bringToFront() {
        bringTabToFront(window, ofApplication: bundleId, named: name)
    }

    // Puts the window back where it was read, for a scene that leaves it elsewhere and is
    // followed by one that reads the frame it started from. The frame is written rather than
    // a hotkey posted: no action takes a window to a frame of the run's choosing, and OttoWM
    // records nothing about a window that is only moved.
    func putBack() {
        eventually("\(name) is back at \(originalFrame)") {
            setAXFrame(of: window, to: originalFrame)

            return isAsItWas ? nil : "\(name) at \(frame().map { "\($0)" } ?? "nowhere")"
        }
    }

    // The hotkeys act on the focused window, and a workspace switch moves the focus to an
    // arbitrary window, so a run that wants this one moved focuses it first.
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
// The desk it sets up is a file browser, a terminal, a browser and an editor, because a
// workspace switch costs what the windows on it cost.
struct Session {
    let ottowm: Process
    // The window the hotkeys move between workspaces.
    let movable: Subject
    // The ones that only move because the workspace they are on was left.
    let others: [Subject]
    // The tab behind one of the desk's windows, for a scene that drives a window its
    // application shows one tab of at a time. Kept out of the desk: a tab that is not in
    // front reports the frame it had when it last was, so a check made over every subject
    // would read a value that cannot change.
    let backgroundTab: Subject?

    private let hiddenEdgeX: CGFloat

    var subjects: [Subject] { others + [movable] }

    // Every instance is a whole desk of its own, so a run at two costs twice what a run at
    // one costs, and the difference between them is what a window adds.
    //
    // An arranged desk is put in the four quarters of the screen instead of wherever macOS
    // placed it, for a run that asserts which window a focus move lands on and has to know
    // the geometry to do it.
    //
    // A tabbed desk shows a second terminal window merged into the first, so the run drives
    // one window its application shows a tab of at a time.
    static func start(instances: Int = 1, arranged: Bool = false, tabbed: Bool = false) -> Session {
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
        // two windows of the same application on screen and the second must not be matched
        // by the first one's title.
        var claimed: [AXUIElement] = []
        let windows = sources.map { source -> (String, String, AXUIElement) in
            let window = openWindow(source, claimed: claimed)
            claimed.append(window)

            return (source.name, source.bundleId, window)
        }

        let tab = tabbed ? stageTab(alongside: windows, claimed: &claimed) : nil

        if arranged { arrange(windows) }

        // Everything is up and nothing else moves on its own, so the frames read now are
        // the ones the windows go back to after every switch.
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

        // The two tabs are one window, so the one behind takes the frame the desk window
        // was arranged to rather than the stale one it reports before it is brought to the
        // front.
        let backgroundTab = tab.map { source, window -> Subject in
            guard let front = subjects.first(where: { $0.bundleId == source.bundleId }) else {
                fail("the desk shows no \(source.bundleId) window for the tab to stand behind")
            }

            return Subject(
                name: source.name, bundleId: source.bundleId, window: window, originalFrame: front.originalFrame
            )
        }

        let session = Session(
            ottowm: ottowm,
            movable: movable,
            others: subjects.dropLast(),
            backgroundTab: backgroundTab,
            hiddenEdgeX: hiddenEdgeX
        )
        session.movable.focus()

        return session
    }

    // The subject opened in the named application, for a scene that drives one of the
    // desk's other windows rather than the movable one.
    func subject(named name: String) -> Subject {
        guard let subject = subjects.first(where: { $0.name == name }) else {
            fail("no subject named \(name)")
        }
        return subject
    }

    // Waits for the focus a hotkey was asked to move, and reports where it actually is
    // when it gives up.
    func expectFocused(_ subject: Subject) {
        eventually("the \(subject.name) window took the focus") { subject.lacksFocus() }
    }

    // Where every window is right now, for the message a wait prints when it gives up.
    var standing: String {
        subjects
            .map { "\($0.name) \(isParked($0) ? "parked" : "at \($0.frame().map { "\($0.origin)" } ?? "nowhere")")" }
            .joined(separator: ", ")
    }

    func isParked(_ subject: Subject) -> Bool {
        guard let frame = subject.frame() else { return false }

        return frame.minX >= hiddenEdgeX - hiddenEdgeMargin
    }

    // Waits for every subject to satisfy the expectation, and reports which ones do not
    // and where they are when it gives up.
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

    // OttoWM puts every parked window back on the way out, so a check of the desk waits
    // for it to exit.
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

// Opens the second terminal window and merges it into the one the desk already shows.
// Merged before the desk is arranged, and with the desk's own window brought back to the
// front after: the merge leaves an arbitrary window in front, and what the run arranges and
// reads afterwards has to be the tab it claimed. The tab bar goes up before
// the second window opens so neither of them changes size when they become tabs.
private func stageTab(
    alongside windows: [(String, String, AXUIElement)], claimed: inout [AXUIElement]
) -> (WindowSource, AXUIElement) {
    let source = stageTabSource()
    showTabBar(ofApplication: source.bundleId, named: source.name)
    let window = openWindow(source, claimed: claimed)
    claimed.append(window)

    mergeIntoTabs(ofApplication: source.bundleId, named: source.name)

    for (name, bundleId, deskWindow) in windows where bundleId == source.bundleId {
        bringTabToFront(deskWindow, ofApplication: bundleId, named: name)
    }

    return (source, window)
}

private func launchOttoWM() -> Process {
    let ottowm = Process()
    ottowm.executableURL = URL(fileURLWithPath: "\(appPath)/Contents/MacOS/OttoWM")
    ottowm.environment = ProcessInfo.processInfo.environment.merging(
        ["XDG_CONFIG_HOME": temporaryDirectory.path]
    ) { _, staged in staged }

    guard (try? ottowm.run()) != nil else { fail("cannot launch \(ottowm.executableURL!.path)") }

    // Waited out rather than only asked to quit, and killed if it does not go: the next
    // harness run refuses to start while an OttoWM is up, and CI runs them back to back.
    // AppKit takes its time with a SIGTERM that lands while the app is still working
    // through the events it was sent.
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
    // hotkey posted in between is lost.
    Thread.sleep(forTimeInterval: tapSettleSeconds)

    return ottowm
}

private func ottowmLog(of pid: pid_t) -> String {
    shell("/usr/bin/log", [
        "show", "--style", "compact", "--last", "5m", "--info", "--debug",
        "--predicate", "subsystem == \"\(bundleId)\" AND processIdentifier == \(pid)",
    ])
}
