import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    private let windowObserver = AXWindowObserver()
    private var hotkeys: HotkeyEventTap?
    private var engine: Engine?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard case let .success(config) = ConfigFile.load() else {
            Log.app.error("unable to load a valid config, exiting")
            exit(EXIT_FAILURE)
        }

        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        )

        // Every AX call is a synchronous IPC round trip, and without a timeout a
        // beachballing application blocks the main thread for as long as it hangs.
        // Set on the system-wide element, this becomes the process-wide default.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), axMessagingTimeoutSeconds)

        Log.app.notice("OttoWM (\(AppInfo.version)) launched, accessibility=\(trusted)")

        let windowById: (CGWindowID) -> AXWindow? = { [windowObserver] id in
            windowObserver.window(byId: id)
        }

        let engine = Engine(
            desktop: OffscreenParkingDesktop(
                screen: MainScreen(),
                window: windowById,
                focusedWindowId: { AXWindow.focused()?.id }
            ),
            screen: Screen(
                focusedWindow: OperationCache { AXWindow.focused()?.snapshot() },
                onScreenWindowIds: OperationCache {
                    Set((CGWindowListCopyWindowInfo(
                        [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                         as? [[String: Any]] ?? [])
                        .compactMap { $0[kCGWindowNumber as String] as? NSNumber }
                        .map { CGWindowID($0.uint32Value) })
                },
                window: windowById
            )
        )
        self.engine = engine

        let windows = windowObserver.start { engine.handle($0) }
        engine.start(windows: windows)

        let hotkeys = HotkeyEventTap(config: config) { action in
            switch action {
            case let .switchToWorkspace(workspace): engine.switchToWorkspace(workspace)
            case let .moveWindowToWorkspace(workspace): engine.moveFocusedWindow(toWorkspace: workspace)
            }
        }
        self.hotkeys = hotkeys

        if !hotkeys.start() {
            Log.app.error("event tap creation failed (check Accessibility permission)")
        }
    }
}
