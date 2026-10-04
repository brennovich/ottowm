import AppKit

/// A clear 1x1 window on the managed native Space. macOS has no public API to switch Spaces, but making a window
/// key switches to the Space the window is on.
///
/// Measured on macOS 26: the Space does not change for a window above the normal level, a non-activating panel, a
/// window with `.stationary` or `.transient`, a window on all Spaces, or an activation without a key window. Mission
/// Control shows the anchor while it is ordered in, even clear, at alpha 0 or off screen, so it stays ordered out
/// between switches. Ordered out, it keeps the Space it was pinned on.
///
/// An active OttoWM without a key window, or with a `.stationary` one, loses the focus to the frontmost window on the
/// Space, which can be parked. Putting the anchor away hands the focus to the Finder desktop instead.
final class SpaceAnchor: Anchor {
    private let display: () -> Display?
    private let log: LogChannel
    private var window: AnchorWindow?

    init(log: LogChannel = Log.desktop, display: @escaping () -> Display?) {
        self.log = log
        self.display = display
    }

    static func frame(on display: Display, primaryHeight: CGFloat) -> CGRect {
        CGRect(origin: display.fullFrame.origin, size: CGSize(width: 1, height: 1)).flipped(primaryHeight: primaryHeight)
    }

    /// A window ordered in joins the Space in front on the display holding it. The display is read at each pin
    /// because its frame can change after the window is made.
    func pin() {
        let window = window ?? AnchorWindow()
        self.window = window
        if let display = display() {
            let primaryHeight = NSScreen.screens.first?.frame.height ?? display.fullFrame.height
            window.setFrame(Self.frame(on: display, primaryHeight: primaryHeight), display: false)
        }
        window.orderFrontRegardless()
        window.orderOut(nil)
        log.debug("anchor pinned on the active Space")
    }

    /// Never pinned, the anchor would be ordered in on the Space in front, which switches nothing.
    func focus() {
        guard let window else {
            log.debug("cannot focus the anchor: not pinned")
            return
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Orders out the anchor a focus ordered in, whatever Space the switch landed on. On macOS 15 OttoWM is
    /// active but the anchor is not key yet when the Space change is posted, so the Finder desktop is focused either way.
    func putAway() {
        guard let window, window.isVisible else { return }

        focusFinderDesktop(log: log)
        window.orderOut(nil)
        log.debug("anchor put away")
    }
}

private final class AnchorWindow: NSPanel {
    init() {
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        // A panel hides when its application deactivates. Ordered in again, it would join the Space in front.
        hidesOnDeactivate = false
    }

    // A borderless window cannot become key by default.
    override var canBecomeKey: Bool { true }
}

private typealias SetFrontProcess = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> Int32

@_silgen_name("GetProcessForPID")
private func getProcessForPID(_ pid: pid_t, _ psn: UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

/// Brings Finder to the front with no key window, the state a click on the desktop leaves. `kCPSNoWindows` (0x400)
/// fronts the process without making any of its windows key; yabai passes it for the same purpose.
private func focusFinderDesktop(log: LogChannel) {
    guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first,
          let setFrontProcess = SkyLight.symbol("_SLPSSetFrontProcessWithOptions", as: SetFrontProcess.self)
    else { return log.error("cannot focus the Finder desktop: Finder or _SLPSSetFrontProcessWithOptions is missing") }

    var psn = ProcessSerialNumber()
    let status = getProcessForPID(finder.processIdentifier, &psn)
    guard status == noErr else { return log.error("cannot focus the Finder desktop: GetProcessForPID failed err=\(status)") }

    let result = setFrontProcess(&psn, 0, 0x400)
    if result != 0 {
        log.error("focusing the Finder desktop failed err=\(result)")
    }
}
