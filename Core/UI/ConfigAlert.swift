import AppKit

/// Displays the config error that stopped the boot, with two interactions:
/// 1. Restart and 2. Quit.
enum ConfigAlert {
    enum Response {
        case restart
        case quit
    }

    static func ask(_ error: ConfigError) -> Response {
        NSApp.setActivationPolicy(.regular)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "OttoWM cannot read its config"
        alert.informativeText = "\(error).\n\nNo key is bound until the file parses. "
            + "Fix it and restart, or quit."
        alert.addButton(withTitle: "Restart OttoWM")
        alert.addButton(withTitle: "Quit")
        alert.layout()

        alert.window.level = .floating
        alert.window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        NSApp.activate(ignoringOtherApps: true)

        let response: Response = alert.runModal() == .alertFirstButtonReturn ? .restart : .quit
        alert.window.orderOut(nil)

        return response
    }
}
