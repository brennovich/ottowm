import AppKit
import Carbon

// The panels OttoWM shows on its own: its on-screen windows by window number and frame,
// read from the window server, which reports frames in top left coordinates already.
// Only the owner, the number and the bounds are read, none of which needs a Screen
// Recording grant.
func pagerWindows(of pid: pid_t) -> [CGWindowID: CGRect] {
    let listed = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []

    return listed.reduce(into: [:]) { windows, window in
        guard window[kCGWindowOwnerPID as String] as? pid_t == pid,
              let number = window[kCGWindowNumber as String] as? CGWindowID,
              let bounds = window[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary)
        else { return }

        windows[number] = frame
    }
}

// The bottom right corner of the display the pager is shown on, which is the main one, in
// the same top left coordinates.
func pagerCorner() -> CGPoint {
    let screen = NSScreen.main ?? NSScreen.screens[0]
    let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height

    return CGPoint(x: screen.frame.maxX, y: primaryHeight - screen.frame.minY)
}

// The window server flag an application sets while a password field has focus. While it is
// set no key event is delivered to an event tap, the hotkeys this run posts included, so a
// scene that takes it releases it before the run goes on, and the cleanup releases it too
// for a run that ends in between.
func holdSecureEventInput() {
    cleanups.append { DisableSecureEventInput() }
    EnableSecureEventInput()
}

func releaseSecureEventInput() {
    DisableSecureEventInput()
}
