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
        alert.accessoryView = monospaced("\(error)", like: textColumn(of: alert))
        alert.layout()

        alert.window.level = .floating
        alert.window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        NSApp.activate(ignoringOtherApps: true)

        let response: Response = alert.runModal() == .alertFirstButtonReturn ? .restart : .dismiss
        alert.window.orderOut(nil)
        NSApp.setActivationPolicy(policy)

        return response
    }

    // macOS 15 centers the text of an alert, macOS 26 aligns it to the left. Copying the
    // width and the alignment of the informative text keeps the error in the same column
    // as the rest of the alert on both. Reading it requires a laid out alert.
    private static func textColumn(of alert: NSAlert) -> (width: CGFloat, alignment: NSTextAlignment) {
        let informative = alert.window.contentView?.subviews
            .compactMap { $0 as? NSTextField }
            .first { $0.stringValue == alert.informativeText }

        guard let informative else { return (errorWidth, .natural) }

        return (informative.frame.width, informative.alignment)
    }

    private static func monospaced(_ text: String, like column: (width: CGFloat, alignment: NSTextAlignment)) -> NSView {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        label.alignment = column.alignment
        // `wrappingLabelWithString` turns the autoresizing mask off, and NSAlert sizes an
        // accessory view from its frame, so the mask goes back on and the frame is set here.
        label.translatesAutoresizingMaskIntoConstraints = true
        label.preferredMaxLayoutWidth = column.width
        label.frame = NSRect(x: 0, y: 0, width: column.width, height: ceil(label.fittingSize.height))

        return label
    }
}
