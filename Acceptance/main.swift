import AppKit

// Drives the installed OttoWM.app the way a user does: real hotkeys through the event
// tap, real windows read back through the accessibility API. Nothing here imports the
// app's own code on purpose, the bundle under test is the one shipped in the release zip.

let appPath = "/Applications/OttoWM.app"
let bundleId = "com.github.brennovich.ottowm"

let pollInterval: TimeInterval = 0.1
let readyTimeout: TimeInterval = 30
let placementTimeout: TimeInterval = 15
let tapSettleSeconds: TimeInterval = 1

// Core/OffscreenParkingDesktop.swift parks a window 1px past the right edge, and macOS
// clamps it back by an unspecified amount. HiddenEdge.holds allows the same 10px.
let hiddenEdgeMargin: CGFloat = 10
let restoreTolerance: CGFloat = 2

var cleanups: [() -> Void] = []

func report(_ message: String) {
    print("acceptance: \(message)")
    fflush(stdout)
}

func fail(_ message: String) -> Never {
    for cleanup in cleanups.reversed() { cleanup() }
    FileHandle.standardError.write(Data("acceptance: FAILED, \(message)\n".utf8))
    exit(EXIT_FAILURE)
}

// The probe returns nil once satisfied, or what it sees right now so an expiry says
// something more useful than "timed out".
func eventually(
    _ description: String,
    timeout: TimeInterval = placementTimeout,
    interval: TimeInterval = pollInterval,
    _ probe: () -> String?
) {
    let deadline = Date().addingTimeInterval(timeout)
    var observed: String?

    repeat {
        observed = probe()
        if observed == nil {
            report("ok, \(description)")
            return
        }
        // NSWorkspace tracks the frontmost application through notifications delivered to
        // the main run loop, so a probe that only sleeps reads the same stale value until
        // the deadline. Waiting on the run loop is what lets those arrive.
        RunLoop.current.run(until: Date().addingTimeInterval(interval))
    } while Date() < deadline

    fail("\(description), gave up after \(Int(timeout))s with \(observed ?? "nothing to report")")
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

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

func axFrame(of window: AXUIElement) -> CGRect? {
    guard let rawPosition = attribute(window, kAXPositionAttribute),
          let rawSize = attribute(window, kAXSizeAttribute),
          CFGetTypeID(rawPosition) == AXValueGetTypeID(),
          CFGetTypeID(rawSize) == AXValueGetTypeID()
    else { return nil }

    var origin = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(rawPosition as! AXValue, .cgPoint, &origin),
          AXValueGetValue(rawSize as! AXValue, .cgSize, &size)
    else { return nil }

    return CGRect(origin: origin, size: size)
}

func windows(ofApplication pid: pid_t) -> [AXUIElement] {
    attribute(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AXUIElement] ?? []
}

func title(of window: AXUIElement) -> String? {
    attribute(window, kAXTitleAttribute) as? String
}

// Only the raw event flags tell the left Option key from the right one, and the bundled
// bindings are all left Option, so the device dependent bits of Core/Config/KeyCombo.swift
// have to be set by hand. System Events cannot produce them.
let leftOptionBit: UInt64 = 0x20
let leftShiftBit: UInt64 = 0x2

let keyCodesByWorkspace: [Int: CGKeyCode] = [1: 18, 2: 19, 3: 20, 4: 21]

func post(_ keyCode: CGKeyCode, _ flags: CGEventFlags) {
    guard let source = CGEventSource(stateID: .hidSystemState) else { fail("cannot create an event source") }

    for keyDown in [true, false] {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else {
            fail("cannot create a key event")
        }
        event.flags = keyDown ? flags : []
        event.post(tap: .cgSessionEventTap)
    }
}

func keyCode(forWorkspace workspace: Int) -> CGKeyCode {
    guard let keyCode = keyCodesByWorkspace[workspace] else { fail("no key bound to workspace \(workspace)") }
    return keyCode
}

func switchToWorkspace(_ workspace: Int) {
    report("posting lopt-\(workspace)")
    post(keyCode(forWorkspace: workspace), CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | leftOptionBit))
}

func moveWindowToWorkspace(_ workspace: Int) {
    report("posting lopt-shift-\(workspace)")
    post(
        keyCode(forWorkspace: workspace),
        CGEventFlags(
            rawValue: CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskShift.rawValue
                | leftOptionBit | leftShiftBit
        )
    )
}

func ottowmLog(of pid: pid_t) -> String {
    shell("/usr/bin/log", [
        "show", "--style", "compact", "--last", "5m", "--info", "--debug",
        "--predicate", "subsystem == \"\(bundleId)\" AND processIdentifier == \(pid)",
    ])
}

// Setup

guard AXIsProcessTrusted() else {
    fail("""
    the harness itself has no Accessibility permission, it cannot post events nor read \
    window frames. Grant it to the terminal running make, or on CI to the process running \
    the acceptance binary.
    """)
}

guard FileManager.default.fileExists(atPath: appPath) else {
    fail("no app at \(appPath), run `make install` first")
}

guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty else {
    fail("another OttoWM is already running, it would race this one for the same hotkeys, quit it first")
}

let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("ottowm-acceptance-\(ProcessInfo.processInfo.processIdentifier)")
let configDirectory = temporaryDirectory.appendingPathComponent("ottowm")

do {
    try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
    // The bundled defaults, read through XDG_CONFIG_HOME so whatever sits in the real
    // ~/.config/ottowm cannot change what this run is bound to.
    try FileManager.default.copyItem(
        at: URL(fileURLWithPath: "\(appPath)/Contents/Resources/ottowm"),
        to: configDirectory.appendingPathComponent("ottowm")
    )
} catch {
    fail("cannot stage the configuration, \(error.localizedDescription)")
}

cleanups.append { try? FileManager.default.removeItem(at: temporaryDirectory) }

let document = temporaryDirectory.appendingPathComponent("acceptance.txt")
guard (try? "OttoWM acceptance".write(to: document, atomically: true, encoding: .utf8)) != nil else {
    fail("cannot write \(document.path)")
}

let ottowm = Process()
ottowm.executableURL = URL(fileURLWithPath: "\(appPath)/Contents/MacOS/OttoWM")
ottowm.environment = ProcessInfo.processInfo.environment.merging(
    ["XDG_CONFIG_HOME": temporaryDirectory.path]
) { _, staged in staged }

guard (try? ottowm.run()) != nil else { fail("cannot launch \(ottowm.executableURL!.path)") }

cleanups.append {
    if ottowm.isRunning { ottowm.terminate() }
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

let textEditWasRunning = !NSRunningApplication
    .runningApplications(withBundleIdentifier: "com.apple.TextEdit").isEmpty

// TextEdit needs a document to open, on an empty invocation it shows the open panel
// instead of a window.
_ = shell("/usr/bin/open", ["-a", "TextEdit", document.path])

var subject: AXUIElement?

// A TextEdit that was already there belongs to whoever opened it, only the window this
// run added goes away.
cleanups.append {
    guard textEditWasRunning else {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit")
            .forEach { $0.terminate() }
        return
    }
    guard let subject, let closeButton = attribute(subject, kAXCloseButtonAttribute) else { return }
    AXUIElementPerformAction(closeButton as! AXUIElement, kAXPressAction as CFString)
}

eventually("TextEdit shows \(document.lastPathComponent)") {
    guard let textEdit = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").first
    else { return "TextEdit is not running" }

    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == textEdit.processIdentifier else {
        return "TextEdit is not frontmost, the hotkeys act on the focused window"
    }

    subject = windows(ofApplication: textEdit.processIdentifier)
        .first { title(of: $0) == document.lastPathComponent }

    return subject == nil ? "no window titled \(document.lastPathComponent)" : nil
}

guard let window = subject, let originalFrame = axFrame(of: window) else {
    fail("cannot read the window frame")
}

let hiddenEdgeX = CGDisplayBounds(CGMainDisplayID()).maxX - 1

report("window at \(originalFrame), hidden edge at x=\(hiddenEdgeX)")

guard originalFrame.minX < hiddenEdgeX - hiddenEdgeMargin else {
    fail("the window already sits at the hidden edge, parking it would prove nothing")
}

func expectFrame(_ description: String, _ satisfies: @escaping (CGRect) -> Bool) {
    eventually(description) {
        guard let frame = axFrame(of: window) else { return "the window is gone" }
        return satisfies(frame) ? nil : "the window is at \(frame)"
    }
}

func isParked(_ frame: CGRect) -> Bool {
    frame.minX >= hiddenEdgeX - hiddenEdgeMargin
}

func isBackWhereItWas(_ frame: CGRect) -> Bool {
    abs(frame.minX - originalFrame.minX) <= restoreTolerance
        && abs(frame.minY - originalFrame.minY) <= restoreTolerance
}

// Scenario, a window sent to another workspace parks at the hidden edge and comes back

moveWindowToWorkspace(2)
expectFrame("the window parked at the hidden edge", isParked)

switchToWorkspace(2)
expectFrame("the window came back to \(originalFrame.origin)", isBackWhereItWas)

switchToWorkspace(1)
expectFrame("the window parked again", isParked)

for cleanup in cleanups.reversed() { cleanup() }

report("PASSED")
