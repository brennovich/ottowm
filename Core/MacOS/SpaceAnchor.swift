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
    private var window: AnchorWindow?

    /// A window ordered in joins the Space in front.
    func pin() {
        let window = window ?? AnchorWindow()
        self.window = window
        window.orderFrontRegardless()
        window.orderOut(nil)
        Log.desktop.debug("anchor pinned on the active Space")
    }

    /// Never pinned, the anchor would be ordered in on the Space in front, which switches nothing.
    func focus() {
        guard let window else {
            Log.desktop.debug("cannot focus the anchor: not pinned")
            return
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Orders out the anchor a focus ordered in, whatever Space the switch landed on. On macOS 15 OttoWM is
    /// active but the anchor is not key yet when the Space change is posted, so the Finder desktop is focused either way.
    func putAway() {
        guard let window, window.isVisible else { return }

        focusFinderDesktop()
        window.orderOut(nil)
        Log.desktop.debug("anchor put away")
    }
}

private final class AnchorWindow: NSPanel {
    init() {
        let top = NSScreen.screens.first?.frame ?? .zero
        super.init(
            contentRect: CGRect(x: top.minX, y: top.maxY - 1, width: 1, height: 1),
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
private func focusFinderDesktop() {
    guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first,
          let setFrontProcess = SkyLight.symbol("_SLPSSetFrontProcessWithOptions", as: SetFrontProcess.self)
    else { return Log.desktop.error("cannot focus the Finder desktop: Finder or _SLPSSetFrontProcessWithOptions is missing") }

    var psn = ProcessSerialNumber()
    let status = getProcessForPID(finder.processIdentifier, &psn)
    guard status == noErr else { return Log.desktop.error("cannot focus the Finder desktop: GetProcessForPID failed err=\(status)") }

    let result = setFrontProcess(&psn, 0, 0x400)
    if result != 0 {
        Log.desktop.error("focusing the Finder desktop failed err=\(result)")
    }
}
