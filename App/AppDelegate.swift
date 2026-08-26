import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    private let registry = WindowRegistry()
    private let screenLock = ScreenLock()
    private lazy var windowObserver = AXWindowObserver(
        registry: registry,
        screenIsLocked: { [screenLock] in screenLock.isLocked }
    )
    private lazy var shutdown = Shutdown(stop: { [weak self] in self?.engine?.stop() })
    private var bindings: Bindings?
    private var engine: Engine?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard case let .success(config) = ConfigFile.load() else {
            Log.app.error("unable to load a valid config, exiting")
            exit(EXIT_FAILURE)
        }

        let permission = AccessibilityPermission.system()
        switch permission.request() {
        case .granted:
            break
        case .relaunching:
            // The relaunch is asynchronous and exits this process once the new
            // instance is on its way, so nothing here may exit before it lands.
            return
        case .quit:
            Log.app.error("unable to acquire accessibility permissions, exiting")
            exit(EXIT_FAILURE)
        }

        // Every AX call is a synchronous IPC round trip; without a timeout a beachballing
        // application blocks the main thread for as long as it hangs. Set on the
        // system-wide element to make it the process-wide default.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), axMessagingTimeoutSeconds)

        Log.app.notice("OttoWM (\(AppInfo.version())) launched")

        let windowById: (CGWindowID) -> AXWindow? = { [registry] id in
            registry.window(for: id)
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
            windowSystem: WindowSystem(
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
            screenIsLocked: { [screenLock] in screenLock.isLocked },
            quit: shutdown.quit,
            restart: { [weak self] in self?.bindings?.reload() }
        )
        self.engine = engine.start(windows: windowObserver.start { engine.handle($0) })

        let bindings = Bindings.system(config: config, handler: engine.handle)
        self.bindings = bindings

        screenLock.startWatching { [windowObserver] in windowObserver.dropDeadWindows() }
        bindings.start()
        shutdown.startWatchingSIGTERM()

        permission.startWatchingTrust(
            lost: { [weak self] in self?.bindings?.stop() },
            regained: { [weak self] in self?.bindings?.start() }
        )
    }
}
