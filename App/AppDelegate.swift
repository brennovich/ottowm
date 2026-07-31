import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    private let windowObserver = AXWindowObserver()
    private var hotkeys: HotkeyEventTap?
    private var engine: Engine?

    func applicationDidFinishLaunching(_ notification: Notification) {
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

        let onScreenWindows = OperationCache { Self.onScreenWindowIds() }

        let desktop = OffscreenParkingDesktop(
            screen: MainScreen(),
            window: windowById,
            onScreenWindowIds: onScreenWindows.value,
            managedWindowIds: { [weak self] in self?.engine?.managedWindowIds ?? [] },
            focusedWindowId: { AXWindow.focused()?.id }
        )

        let engine = Engine(
            desktop: desktop,
            window: windowById,
            focusedWindow: OperationCache { AXWindow.focused()?.snapshot() },
            onScreenWindows: onScreenWindows
        )
        self.engine = engine

        let windows = windowObserver.start { engine.handle($0) }
        engine.start(windows: windows)

        let hotkeys = HotkeyEventTap { action in
            switch action {
            case let .switchToVirtualSpace(virtualSpace):
                engine.switchToVirtualSpace(virtualSpace)
            case let .moveWindowToVirtualSpace(virtualSpace):
                engine.moveWindowToVirtualSpace(nil, virtualSpace)
            }
        }
        self.hotkeys = hotkeys

        if hotkeys.start() {
            Log.app.notice("hotkeys active")
        } else {
            Log.app.error("event tap creation failed (check Accessibility permission)")
        }
    }

    private static func onScreenWindowIds() -> Set<CGWindowID> {
        guard let infoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else {
            Log.app.error("CGWindowListCopyWindowInfo returned nil")
            return []
        }

        return OttoWM.onScreenWindowIds(from: infoList)
    }
}
