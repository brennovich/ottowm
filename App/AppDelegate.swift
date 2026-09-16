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

        let windowSystem = WindowSystem.system(windowEvents: windowEvents, applications: applications)
        let pager = Pager()
        let desktop = parkingDesktop(spacing: config.spacing, pager: pager)

        let engine = Engine.system(
            desktop: desktop,
            windowSystem: windowSystem,
            workspaces: Workspaces(
                tabGroups: TabGroups(tabCount: windowSystem.tabCount(of:), frame: windowSystem.frame(of:)),
                switched: pager.show(workspace:)
            ),
            screenIsLocked: { [lifecycle] in lifecycle.screenIsLocked }
        )
        engine.start(windows: applicationsObserver.start { engine.handle($0) })
        self.engine = engine
        pager.isShown = config.showsPager

        let bindings = Bindings.system(
            config: config,
            reloaded: {
                pager.isShown = $0.showsPager
                desktop.spacing = $0.spacing
            },
            handler: { [lifecycle] binding in
                switch binding {
                case let .action(action): engine.handle(action)
                case .quit: lifecycle.quit()
                case .restart: lifecycle.reload()
                }
            }
        )
        self.bindings = bindings

        bindings.start()
        lifecycle.startWatchingSIGTERM()
        lifecycle.startWatchingScreenLock()

        permission.startWatchingTrust(
            lost: { [weak self] in self?.bindings?.stop() },
            regained: { [weak self] in self?.bindings?.start() }
        )
    }

    private func parkingDesktop(spacing: CGFloat, pager: Pager) -> OffscreenParkingDesktop {
        OffscreenParkingDesktop(
            screens: MainScreen(),
            window: applications.findWindow(by:),
            spacing: spacing,
            displayChanged: pager.place(on:)
        )
    }
}
