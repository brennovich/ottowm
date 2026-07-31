import AppKit
import CoreGraphics

enum WindowEvent {
    case created(WindowSnapshot)
    case focused(WindowSnapshot)
    case destroyed(CGWindowID)
}

func shouldObserveApplication(activationPolicy: NSApplication.ActivationPolicy, pid: pid_t, ownPid: pid_t) -> Bool {
    activationPolicy == .regular && pid != ownPid
}
