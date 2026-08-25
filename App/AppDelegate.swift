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
    private var termination: (any DispatchSourceSignal)?

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
            quit: {
                Log.app.notice("quit action received, window frames restored")
                exit(EXIT_SUCCESS)
            },
            restart: { [weak self] in self?.reloadConfig() }
        )
        self.engine = engine.start(windows: windowObserver.start { engine.handle($0) })
        self.hotkeys = Hotkeys(keyCodeMatcher: config.action, handler: engine.handle)

        screenLock.startWatching { [windowObserver] in windowObserver.dropDeadWindows() }
        startHotkeys()
        startWatchingSIGTERM()

        permission.startWatchingTrust(
            lost: { [weak self] in self?.hotkeys?.stop() },
            regained: { [weak self] in self?.startHotkeys() }
        )
    }

    private func startWatchingSIGTERM() {
        signal(SIGTERM, SIG_IGN)
        let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        termination.setEventHandler { [weak self] in
            Log.app.notice("SIGTERM received, restoring window frames")
            self?.engine?.stop()
            exit(EXIT_SUCCESS)
        }
        termination.resume()
        self.termination = termination
    }

    private func reloadConfig() {
        guard let engine else { return }
        guard case let .success(config) = ConfigFile.load() else {
            Log.app.error("unable to load a valid config, keeping the bindings already up")
            return
        }

        hotkeys?.stop()
        hotkeys = Hotkeys(keyCodeMatcher: config.action, handler: engine.handle)
        startHotkeys()
        Log.app.notice("config reloaded")
    }

    private func startHotkeys() {
        if hotkeys?.start() != true {
            Log.app.error("event tap creation failed (check Accessibility permission)")
        }
    }
}
