import AppKit

/// Displays the config error that stopped a load, with two interactions:
/// 1. Restart and 2. dismiss, which quits at boot and keeps the bindings
/// already up on a reload.
///
/// - Returns:
///   - `.restart`: relaunch OttoWM.
///   - `.dismiss`: the alert was dismissed.
enum ConfigAlert {
    enum Request {
        case boot
        case reload
    }

    enum Response {
        case restart
        case dismiss
    }

    private static let errorWidth: CGFloat = 260

    static func ask(_ error: ConfigError, _ request: Request) -> Response {
        let policy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "OttoWM cannot read its config"
        alert.accessoryView = monospaced("\(error)")

        switch request {
        case .boot:
            alert.informativeText = "No key is bound until the file parses. Fix it and restart, or quit."
            alert.addButton(withTitle: "Restart OttoWM")
            alert.addButton(withTitle: "Quit")
        case .reload:
            alert.informativeText = "The bindings already up stay in place. Fix the file and restart, or keep them."
            alert.addButton(withTitle: "Restart OttoWM")
            alert.addButton(withTitle: "Keep bindings")
        }

        alert.layout()

        alert.window.level = .floating
        alert.window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        NSApp.activate(ignoringOtherApps: true)

        let response: Response = alert.runModal() == .alertFirstButtonReturn ? .restart : .dismiss
        alert.window.orderOut(nil)
        NSApp.setActivationPolicy(policy)

        return response
    }

    private static func monospaced(_ text: String) -> NSView {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        label.alignment = .center
        // `wrappingLabelWithString` turns the autoresizing mask off, and NSAlert sizes an
        // accessory view from its frame, so the mask goes back on and the frame is set here.
        label.translatesAutoresizingMaskIntoConstraints = true
        label.preferredMaxLayoutWidth = errorWidth
        label.frame = NSRect(x: 0, y: 0, width: errorWidth, height: ceil(label.fittingSize.height))

        return label
    }
}
