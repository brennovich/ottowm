import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    private let applications = Applications()
    private lazy var lifecycle: Lifecycle = Lifecycle(
        stop: { [weak self] in self?.engine?.stop() },
        resume: { [weak self] in
            guard let self else { return }
            engine?.resync(windows: applicationsObserver.resync())
        },
        reloadBindings: { [weak self] in self?.bindings?.reload() }
    )
    private lazy var windowEvents = AXWindowEvents(
        applications: applications,
        screenIsLocked: { [lifecycle] in lifecycle.screenIsLocked }
    )
    private lazy var applicationsObserver = RunningApplicationsObserver(windowEvents: windowEvents)
    private var bindings: Bindings?
    private var engine: Engine?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let config: Config
        switch ConfigGate(relaunch: lifecycle.relaunch).load() {
        case let .loaded(loaded):
            config = loaded
        case .relaunching:
            return
        case .quit:
            Log.app.error("unable to load a valid config, exiting")
            exit(EXIT_FAILURE)
        }

        let permission = AccessibilityPermission(relaunch: lifecycle.relaunch)
        switch permission.request() {
        case .granted:
            break
        case .relaunching:
            return
        case .quit:
            Log.app.error("unable to acquire accessibility permissions, exiting")
            exit(EXIT_FAILURE)
        }

        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), axMessagingTimeoutSeconds)

        Log.app.notice("OttoWM (\(AppInfo.version())) launched")

        let windowSystem = WindowSystem(
            focusedWindow: OperationCache(windowEvents.adoptFocusedWindow),
            onScreenWindows: OperationCache {
                let onScreen = trace(.read, "CGWindowList") {
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
            window: applications.findWindow(by:)
        )

        let engine = Engine.system(
            desktop: OffscreenParkingDesktop(
                screen: MainScreen(),
                window: applications.findWindow(by:)
            ),
            windowSystem: windowSystem,
            workspaces: Workspaces(tabCount: windowSystem.tabCount(of:)),
            screenIsLocked: { [lifecycle] in lifecycle.screenIsLocked },
            quit: lifecycle.quit,
            restart: { [lifecycle] in lifecycle.reload() }
        )
        engine.start(windows: applicationsObserver.start { engine.handle($0) })
        self.engine = engine

        let bindings = Bindings.system(config: config, handler: engine.handle)
        self.bindings = bindings

        bindings.start()
        lifecycle.startWatchingSIGTERM()
        lifecycle.startWatchingScreenLock()

        permission.startWatchingTrust(
            lost: { [weak self] in self?.bindings?.stop() },
            regained: { [weak self] in self?.bindings?.start() }
        )
    }
}
