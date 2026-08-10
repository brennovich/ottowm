import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    private let registry = WindowRegistry()
    private let screenLock = ScreenLock()
    private lazy var windowObserver = AXWindowObserver(
        registry: registry,
        screenIsLocked: { [screenLock] in screenLock.isLocked }
    )
    private var hotkeys: Hotkeys?
    private var engine: Engine?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard case let .success(config) = ConfigFile.load() else {
            Log.app.error("unable to load a valid config, exiting")
            exit(EXIT_FAILURE)
        }

        let permission = AccessibilityPermission.system()
        guard permission.resolve() else { return }

        // Every AX call is a synchronous IPC round trip, and without a timeout a
        // beachballing application blocks the main thread for as long as it hangs.
        // Set on the system-wide element, this becomes the process-wide default.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), axMessagingTimeoutSeconds)

        Log.app.notice("OttoWM (\(AppInfo.version)) launched")

        let windowById: (CGWindowID) -> AXWindow? = { [registry] id in
            registry.window(byId: id)
        }
        let adoptFocusedWindow: () -> AXWindow? = { [windowObserver] in
            windowObserver.adoptFocusedWindow()
        }

        let engine = Engine(
            desktop: OffscreenParkingDesktop(
                screen: MainScreen(),
                window: windowById,
                focusedWindowId: { AXWindow.focused()?.id }
            ),
            screen: Screen(
                focusedWindow: OperationCache { adoptFocusedWindow()?.snapshot() },
                onScreenWindowIds: OperationCache {
                    Set((CGWindowListCopyWindowInfo(
                        [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                         as? [[String: Any]] ?? [])
                        .compactMap { $0[kCGWindowNumber as String] as? NSNumber }
                        .map { CGWindowID($0.uint32Value) })
                },
                window: windowById
            ),
            screenIsLocked: { [screenLock] in screenLock.isLocked }
        )
        self.engine = engine.start(windows: windowObserver.start { engine.handle($0) })
        self.hotkeys = Hotkeys(keyCodeMatcher: config.action, handler: engine.handle)

        // Whatever happened behind the lock screen was not believed while it was up.
        screenLock.startWatching { [windowObserver] in windowObserver.dropDeadWindows() }

        startHotkeys()

        permission.watchTrust(
            lost: { [weak self] in self?.hotkeys?.stop() },
            regained: { [weak self] in self?.startHotkeys() }
        )
    }

    private func startHotkeys() {
        if hotkeys?.start() != true {
            Log.app.error("event tap creation failed (check Accessibility permission)")
        }
    }
}
