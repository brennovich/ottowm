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
        dismiss: { [self] done in pagers.dismiss(then: done) }
    )
    private lazy var windowEvents = AXWindowEvents(
        applications: applications,
        screenIsLocked: { [lifecycle] in lifecycle.screenIsLocked }
    )
    private lazy var applicationsObserver = RunningApplicationsObserver(windowEvents: windowEvents)
    private var bindings: Bindings?
    private var displays: Displays?
    private let pagers = Pagers()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let permission = AccessibilityPermission(ask: AccessibilityAlert.ask, relaunch: lifecycle.relaunch)
        guard let config = ConfigGate(ask: { ConfigAlert.ask($0, .boot) }, relaunch: lifecycle.relaunch).load().configOrExit(),
              permission.request().isGrantedOrExit()
        else { return }

        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), axMessagingTimeoutSeconds)

        Log.app.notice("OttoWM (\(AppInfo.version())) launched")

        let layouts = DisplayLayouts()
        var desktops: [DisplayID: ParkingDesktop] = [:]
        var spacing = config.spacing
        // No property: the watch retains the instance it runs on.
        let secureInput = SecureInput()
        let status = status(secureInput: secureInput)
        let displays = Displays(
            screens: .system,
            windowSystem: WindowSystem.system(windowEvents: windowEvents, applications: applications),
            screenIsLocked: { [lifecycle] in lifecycle.screenIsLocked },
            write: stateFile.save,
            removed: { [pagers] displayId in
                desktops[displayId] = nil
                pagers.remove(on: displayId)
            },
            engine: { [self] display, windowSystem, save in
                let parts = engine(on: display, windowSystem: windowSystem, layouts: layouts, spacing: spacing, save: save)
                desktops[display.id] = parts.desktop
                let pager = Pager(
                    workspaces: parts.workspaces,
                    desktop: parts.desktop,
                    startWatchingWindows: windowEvents.startWatching,
                    windowFrames: pagers.windowFrames,
                    startWatchingSecureInput: secureInput.startWatching,
                    optionClicked: status.toggle
                )
                pagers.add(pager, on: display.id)
                return (parts.workspaces, parts.desktop, parts.engine)
            }
        )

        displays.start(windows: applicationsObserver.start { displays.handle($0) }, restoring: stateFile.load())
        self.displays = displays
        // A crash runs no quit handler, so the state is also saved on a timer.
        Timer.scheduledTimer(withTimeInterval: stateSaveInterval, repeats: true) { _ in displays.saveState() }

        let apply = { [pagers] (config: Config) in
            pagers.isEnabled = config.showsPager
            spacing = config.spacing
            for desktop in desktops.values { desktop.spacing = spacing }
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
        let tag = String(display.id.rawValue.prefix(8))
        let desktop = ParkingDesktop(
            display: display,
            window: applications.findWindow(by:),
            spacing: spacing,
            log: Log.desktop.tagged(tag)
        )
        let workspaces = Workspaces(
            tabGroups: TabGroups(tabCount: windowSystem.tabCount(of:), frame: windowSystem.frame(of:))
        )
        let engine = Engine.system(
            desktop: desktop,
            windowSystem: windowSystem,
            workspaces: workspaces,
            layouts: layouts,
            screenIsLocked: { [lifecycle] in lifecycle.screenIsLocked },
            save: save,
            log: Log.engine.tagged(tag)
        )
        return (desktop, workspaces, engine)
    }

    private func status(secureInput: SecureInput) -> Status {
        Status(
            sources: StatusSources(
                hotkeysListening: { [self] in bindings?.isRunning ?? false },
                secureInputHeld: secureInput.isActive,
                display: {
                    Screens.system.all()
                        .map { "\(Int($0.fullFrame.width))×\(Int($0.fullFrame.height))" }
                        .joined(separator: ", ")
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
