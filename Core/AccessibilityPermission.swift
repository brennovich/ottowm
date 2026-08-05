import AppKit
import ApplicationServices

// Posted by the system whenever the accessibility trust database changes,
// for any application and without a payload. Undeclared by any header, and the
// state it announces is not readable by this process for a moment after it
// lands, hence the settle delay before the trust is read back.
private let accessibilityChangeNotification = "com.apple.accessibility.api"
private let accessibilityGrantSettleSeconds = 1.0

private let accessibilitySettingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

struct AccessibilityPermission {
    enum Request {
        case openSettings
        case restart
    }

    enum Response {
        case confirm
        case quit
    }

    let isTrusted: () -> Bool
    let ask: (Request) -> Response
    let openSettings: () -> Void
    let watchForChange: (@escaping () -> Void) -> Void
    let relaunch: () -> Void
    let quit: () -> Void

    func resolve() -> Bool {
        if isTrusted() { return true }

        Log.app.notice("accessibility permission missing")

        // Watched before the first alert, so a grant made while one is up still
        // relaunches. Once is enough: the process is on its way out by then.
        var relaunching = false
        watchForChange {
            guard !relaunching, self.isTrusted() else { return }
            relaunching = true
            Log.app.notice("accessibility permission granted, relaunching")
            self.relaunch()
        }

        if ask(.openSettings) == .quit {
            quit()
            return false
        }

        openSettings()

        if ask(.restart) == .quit {
            quit()
            return false
        }

        // Unconditional: a restart without the grant lands back on this gate,
        // which beats a button that does nothing.
        relaunching = true
        relaunch()

        return false
    }
}

extension AccessibilityPermission {
    static func system() -> AccessibilityPermission {
        AccessibilityPermission(
            isTrusted: { AXIsProcessTrusted() },
            ask: { alertResponse(to: $0) },
            openSettings: { NSWorkspace.shared.open(URL(string: accessibilitySettingsURL)!) },
            watchForChange: { changed in
                DistributedNotificationCenter.default().addObserver(
                    forName: Notification.Name(accessibilityChangeNotification),
                    object: nil,
                    queue: .main
                ) { _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + accessibilityGrantSettleSeconds, execute: changed)
                }
            },
            relaunch: {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.createsNewApplicationInstance = true
                NSWorkspace.shared.openApplication(
                    at: Bundle.main.bundleURL, configuration: configuration
                ) { _, _ in exit(EXIT_SUCCESS) }
            },
            quit: { exit(EXIT_SUCCESS) }
        )
    }
}

private func alertResponse(to request: AccessibilityPermission.Request) -> AccessibilityPermission.Response {
    // An LSUIElement agent takes a regular activation policy for as long as it is
    // asking: the Dock icon it brings is the way out for a user who walks away
    // from the alert.
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)

    let alert = NSAlert()
    alert.alertStyle = .warning

    switch request {
    case .openSettings:
        alert.messageText = "OttoWM needs Accessibility permission"
        alert.informativeText = "Without it OttoWM cannot see or move a single window. Add OttoWM under Privacy & Security → Accessibility."
        alert.addButton(withTitle: "Open System Settings")
    case .restart:
        alert.messageText = "Grant access"
        alert.informativeText = "OttoWM restarts on its own once the permission is granted. Use this if it does not."
        alert.addButton(withTitle: "Restart OttoWM")
    }

    alert.addButton(withTitle: "Quit")

    alert.layout()

    return alert.runModal() == .alertFirstButtonReturn ? .confirm : .quit
}
