import AppKit

/// Displays to the user that OttoWM requires accessibility permissions, there
/// are three interactions: 1. Open Settings, 2. Restart and 3. Quit.
///
/// - Returns:
///   - `.confirm`: proceed with action.
///   - `.quit`: alert was dismissed.
enum AccessibilityAlert {
    enum Request {
        case openSettings
        case restart
    }

    enum Response {
        case confirm
        case quit
    }

    static func ask(_ request: Request) -> Response {
        NSApp.setActivationPolicy(.regular)

        let alert = NSAlert()
        alert.alertStyle = .warning

        switch request {
        case .openSettings:
            alert.messageText = "OttoWM needs Accessibility permission"
            alert.informativeText = "Without it OttoWM cannot see or move a single window. "
                + "Add OttoWM under Privacy & Security → Accessibility."
            alert.addButton(withTitle: "Open System Settings")
        case .restart:
            alert.messageText = "Grant access"
            alert.informativeText = "OttoWM restarts on its own once the permission is granted. Use this if it does not."
            alert.addButton(withTitle: "Restart OttoWM")
        }

        alert.addButton(withTitle: "Quit")
        alert.layout()

        alert.window.level = .floating
        alert.window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        if request == .openSettings {
            NSApp.activate(ignoringOtherApps: true)
        }

        let response: Response = alert.runModal() == .alertFirstButtonReturn ? .confirm : .quit
        alert.window.orderOut(nil)

        return response
    }
}
