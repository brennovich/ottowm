import AppKit
import CoreGraphics

enum WindowEvent {
    case created(any Window)
    case focused(any Window)
    case destroyed(CGWindowID)
}

func shouldObserveApplication(activationPolicy: NSApplication.ActivationPolicy, pid: pid_t, ownPid: pid_t) -> Bool {
    activationPolicy == .regular && pid != ownPid
}
