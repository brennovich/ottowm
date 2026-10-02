import Cocoa

private let stateSaveInterval: TimeInterval = 10

class AppDelegate: NSObject, NSApplicationDelegate {
    private let applications = Applications()
    private let stateFile = StateFile()
    private lazy var lifecycle: Lifecycle = Lifecycle(
        stop: { [self] in displays?.stop() },
        resume: { [self] in displays?.resync(windows: applicationsObserver.resync()) },
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
    private var displays: Displays?
    private var pager: Pager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let permission = AccessibilityPermission(ask: AccessibilityAlert.ask, relaunch: lifecycle.relaunch)
        guard let config = ConfigGate(ask: { ConfigAlert.ask($0, .boot) }, relaunch: lifecycle.relaunch).load().configOrExit(),
              permission.request().isGrantedOrExit()
        else { return }

        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), axMessagingTimeoutSeconds)

        Log.app.notice("OttoWM (\(AppInfo.version())) launched")

        let layouts = DisplayLayouts()
        var built: [(desktop: ParkingDesktop, workspaces: Workspaces)] = []
        let displays = Displays(
            screens: .system,
            windowSystem: WindowSystem.system(windowEvents: windowEvents, applications: applications),
            write: stateFile.save
        ) { display, windowSystem, save in
            let parts = engine(on: display, windowSystem: windowSystem, layouts: layouts, spacing: config.spacing, save: save)
            built.append((parts.desktop, parts.workspaces))
            return (parts.workspaces, parts.engine)
        }
        // The Pager and the status show the primary display until each display has its own.
        let primary = built[0]
        // No property: the watch retains the instance it runs on.
        let secureInput = SecureInput()
        let status = status(desktop: primary.desktop, secureInput: secureInput)
        let pager = Pager(
            workspaces: primary.workspaces,
            desktop: primary.desktop,
            startWatchingWindows: windowEvents.startWatching,
            startWatchingSecureInput: secureInput.startWatching,
            optionClicked: status.toggle
        )
        self.pager = pager

        displays.start(windows: applicationsObserver.start { displays.handle($0) }, restoring: stateFile.load())
        self.displays = displays
        // A crash runs no quit handler, so the state is also saved on a timer.
        Timer.scheduledTimer(withTimeInterval: stateSaveInterval, repeats: true) { _ in displays.saveState() }

        let apply = { (config: Config) in
            pager.isEnabled = config.showsPager
            for (desktop, _) in built { desktop.spacing = config.spacing }
        }
        apply(config)

        let bindings = Bindings.system(config: config) { [lifecycle] binding in
            switch binding {
            case let .action(action): displays.handle(action)
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

    private func engine(
        on display: Display,
        windowSystem: WindowSystem,
        layouts: DisplayLayouts,
        spacing: CGFloat,
        save: @escaping (SavedState) -> Void
    ) -> (desktop: ParkingDesktop, workspaces: Workspaces, engine: Engine) {
        let desktop = ParkingDesktop(display: display, window: applications.findWindow(by:), spacing: spacing)
        let workspaces = Workspaces(
            tabGroups: TabGroups(tabCount: windowSystem.tabCount(of:), frame: windowSystem.frame(of:))
        )
        let engine = Engine.system(
            desktop: desktop,
            windowSystem: windowSystem,
            workspaces: workspaces,
            layouts: layouts,
            screenIsLocked: { [lifecycle] in lifecycle.screenIsLocked },
            save: save
        )
        return (desktop, workspaces, engine)
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
