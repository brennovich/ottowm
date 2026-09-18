import Cocoa

private let stateSaveInterval: TimeInterval = 10

class AppDelegate: NSObject, NSApplicationDelegate {
    private let applications = Applications()
    private let stateFile = StateFile()
    private lazy var lifecycle: Lifecycle = Lifecycle(
        stop: { [weak self] in self?.engine?.stop() },
        resume: { [weak self] in
            guard let self else { return }
            engine?.resync(windows: applicationsObserver.resync())
        },
        reloadBindings: { [weak self] in self?.bindings?.reload() },
        dismiss: { [weak self] done in
            guard let pager = self?.pager else { return done() }
            pager.dismiss(then: done)
        }
    )
    private lazy var windowEvents = AXWindowEvents(
        applications: applications,
        screenIsLocked: { [lifecycle] in lifecycle.screenIsLocked }
    )
    private lazy var applicationsObserver = RunningApplicationsObserver(windowEvents: windowEvents)
    private var bindings: Bindings?
    private var engine: Engine?
    private var pager: Pager?

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
        let desktop = parkingDesktop(spacing: config.spacing)
        let workspaces = Workspaces(
            tabGroups: TabGroups(tabCount: windowSystem.tabCount(of:), frame: windowSystem.frame(of:))
        )
        let pager = Pager(workspaces: workspaces, desktop: desktop)
        self.pager = pager

        let engine = engine(desktop: desktop, windowSystem: windowSystem, workspaces: workspaces)
        engine.start(windows: applicationsObserver.start { engine.handle($0) }, restoring: stateFile.load())
        self.engine = engine
        // A crash runs no quit handler, so the state is also saved on a timer.
        Timer.scheduledTimer(withTimeInterval: stateSaveInterval, repeats: true) { _ in engine.saveState() }
        pager.isEnabled = config.showsPager

        let bindings = Bindings.system(config: config) { [lifecycle] binding in
            switch binding {
            case let .action(action): engine.handle(action)
            case .quit: lifecycle.quit()
            case .restart: lifecycle.reload()
            }
        }
        bindings.startWatching { config in
            pager.isEnabled = config.showsPager
            desktop.spacing = config.spacing
        }
        self.bindings = bindings

        bindings.start()
        lifecycle.startWatchingSIGTERM()
        lifecycle.startWatchingScreenLock()

        permission.startWatchingTrust(
            lost: { [weak self] in self?.bindings?.stop() },
            regained: { [weak self] in self?.bindings?.start() }
        )
    }

    private func engine(desktop: any Desktop, windowSystem: WindowSystem, workspaces: Workspaces) -> Engine {
        Engine.system(
            desktop: desktop,
            windowSystem: windowSystem,
            workspaces: workspaces,
            screenIsLocked: { [lifecycle] in lifecycle.screenIsLocked },
            save: stateFile.save
        )
    }

    private func parkingDesktop(spacing: CGFloat) -> ParkingDesktop {
        ParkingDesktop(
            screens: MainScreen(),
            window: applications.findWindow(by:),
            spacing: spacing
        )
    }
}
