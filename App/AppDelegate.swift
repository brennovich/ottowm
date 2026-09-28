import Cocoa

private let stateSaveInterval: TimeInterval = 10

class AppDelegate: NSObject, NSApplicationDelegate {
    private let applications = Applications()
    private let stateFile = StateFile()
    private lazy var lifecycle: Lifecycle = Lifecycle(
        stop: { [self] in engine?.stop() },
        resume: { [self] in engine?.resync(windows: applicationsObserver.resync()) },
        reloadBindings: { [self] in bindings?.reload() },
        ask: { ConfigAlert.ask($0, .reload) },
        dismiss: { [self] done in pager?.dismiss(then: done) ?? done() }
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
        let permission = AccessibilityPermission(ask: AccessibilityAlert.ask, relaunch: lifecycle.relaunch)
        guard let config = ConfigGate(ask: { ConfigAlert.ask($0, .boot) }, relaunch: lifecycle.relaunch).load().configOrExit(),
              permission.request().isGrantedOrExit()
        else { return }

        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), axMessagingTimeoutSeconds)

        Log.app.notice("OttoWM (\(AppInfo.version())) launched")

        let windowSystem = WindowSystem.system(windowEvents: windowEvents, applications: applications)
        let desktop = ParkingDesktop(window: applications.findWindow(by:), spacing: config.spacing)
        let workspaces = Workspaces(
            tabGroups: TabGroups(tabCount: windowSystem.tabCount(of:), frame: windowSystem.frame(of:))
        )
        // No property: the watch retains the instance it runs on.
        let secureInput = SecureInput()
        let status = status(desktop: desktop, secureInput: secureInput)
        let pager = Pager(
            workspaces: workspaces,
            desktop: desktop,
            startWatchingWindows: windowEvents.startWatching,
            startWatchingSecureInput: secureInput.startWatching,
            optionClicked: status.toggle
        )
        self.pager = pager

        let engine = Engine.system(
            desktop: desktop,
            windowSystem: windowSystem,
            workspaces: workspaces,
            screenIsLocked: { [lifecycle] in lifecycle.screenIsLocked },
            save: stateFile.save
        )
        engine.start(windows: applicationsObserver.start { engine.handle($0) }, restoring: stateFile.load())
        self.engine = engine
        // A crash runs no quit handler, so the state is also saved on a timer.
        Timer.scheduledTimer(withTimeInterval: stateSaveInterval, repeats: true) { _ in engine.saveState() }

        let apply = { (config: Config) in
            pager.isEnabled = config.showsPager
            desktop.spacing = config.spacing
        }
        apply(config)

        let bindings = Bindings.system(config: config) { [lifecycle] binding in
            switch binding {
            case let .action(action): engine.handle(action)
            case .quit: lifecycle.quit()
            case .restart: lifecycle.reload()
            case .about: status.toggle()
            }
        }
        bindings.startWatching(apply)
        self.bindings = bindings

        bindings.start()
        lifecycle.startWatchingSIGTERM()
        lifecycle.startWatchingScreenLock()
        permission.startWatchingTrust(lost: bindings.stop, regained: bindings.start)
    }

    private func status(desktop: any Desktop, secureInput: SecureInput) -> Status {
        Status(
            sources: StatusSources(
                hotkeysListening: { [self] in bindings?.isRunning ?? false },
                secureInputHeld: secureInput.isActive,
                display: {
                    let size = desktop.display.fullFrame.size
                    return "\(Int(size.width))×\(Int(size.height))"
                },
                configError: { [self] in bindings?.lastError }
            ),
            reload: lifecycle.reload
        )
    }
}

private extension ConfigGate.Outcome {
    func configOrExit() -> Config? {
        switch self {
        case let .loaded(config):
            return config
        case .relaunching:
            return nil
        case .quit:
            Log.app.error("unable to load a valid config, exiting")
            exit(EXIT_FAILURE)
        }
    }
}

private extension AccessibilityPermission.Outcome {
    func isGrantedOrExit() -> Bool {
        switch self {
        case .granted:
            return true
        case .relaunching:
            return false
        case .quit:
            Log.app.error("unable to acquire accessibility permissions, exiting")
            exit(EXIT_FAILURE)
        }
    }
}
