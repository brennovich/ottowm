import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    private let screenLock = ScreenLock()
    private lazy var knownWindows = KnownWindows(screenIsLocked: { [screenLock] in screenLock.isLocked })
    private lazy var windowObserver = AXWindowObserver(knownWindows: knownWindows)
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
            // The relaunch is asynchronous and exits this process once the new instance
            // is on its way. Nothing here may exit before that.
            return
        case .quit:
            Log.app.error("unable to acquire accessibility permissions, exiting")
            exit(EXIT_FAILURE)
        }

        // Every AX call is a synchronous IPC round trip. Without a timeout a hung
        // application blocks the main thread for as long as it hangs. Setting it on the
        // system-wide element makes it the process-wide default.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), axMessagingTimeoutSeconds)

        Log.app.notice("OttoWM (\(AppInfo.version())) launched")

        let windowById: (CGWindowID) -> AXWindow? = { [knownWindows] id in
            knownWindows.window(for: id)
        }

        let engine = Engine(
            desktop: OffscreenParkingDesktop(
                screen: MainScreen(),
                window: windowById,
                focusedWindowId: { AXWindow.focused()?.id }
            ),
            windowSystem: WindowSystem(
                focusedWindow: OperationCache { [knownWindows] in knownWindows.adoptFocused()?.snapshot() },
                onScreenWindows: OperationCache {
                    let onScreen = RoundTrips.shared.measure(.read, "CGWindowList") {
                        CGWindowListCopyWindowInfo(
                            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
                        ) as? [[String: Any]] ?? []
                    }

                    return onScreen.reduce(into: [CGWindowID: CGRect]()) { frames, info in
                        guard let number = info[kCGWindowNumber as String] as? NSNumber,
                              let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                              let frame = CGRect(dictionaryRepresentation: bounds)
                        else { return }

                        frames[CGWindowID(number.uint32Value)] = frame
                    }
                },
                window: windowById
            ),
            screenIsLocked: { [screenLock] in screenLock.isLocked },
            quit: shutdown.quit,
            restart: { [weak self] in self?.bindings?.reload() }
        )
        engine.start(windows: windowObserver.start { engine.handle($0) })
        self.engine = engine

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
