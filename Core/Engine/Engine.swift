import CoreGraphics
import Foundation

final class Engine {
    private let desktop: any Desktop
    private let windowSystem: WindowSystem
    private let workspaces: Workspaces
    private let managed: ManagedWindows
    private let enrollment: WindowEnrollment
    private let navigation: Navigation
    private let fullScreenReturns: FullScreenReturns
    private let screenIsLocked: () -> Bool
    private let quit: () -> Void
    private let restart: () -> Void

    init(
        desktop: any Desktop,
        windowSystem: WindowSystem,
        workspaces: Workspaces,
        managed: ManagedWindows,
        enrollment: WindowEnrollment,
        navigation: Navigation,
        fullScreenReturns: FullScreenReturns,
        screenIsLocked: @escaping () -> Bool,
        quit: @escaping () -> Void,
        restart: @escaping () -> Void
    ) {
        self.desktop = desktop
        self.windowSystem = windowSystem
        self.workspaces = workspaces
        self.managed = managed
        self.enrollment = enrollment
        self.navigation = navigation
        self.fullScreenReturns = fullScreenReturns
        self.screenIsLocked = screenIsLocked
        self.quit = quit
        self.restart = restart
    }

    func start(windows: [WindowSnapshot]) {
        windowSystem.duringOperation("start") {
            for win in desktop.recover(windows) {
                managed.assign(win, to: 1)
            }

            desktop.startWatching { [weak self] in
                guard let self else { return }

                self.windowSystem.duringOperation("native-space-change") {
                    guard let focused = self.windowSystem.focused(),
                          self.managed.placement(of: focused.id) == .parked
                    else {
                        Log.engine.debug("native space change: no parked window focused")
                        self.fullScreenReturns.followWithRetries()
                        self.desktop.repark(self.managed.parked)
                        return
                    }

                    Log.engine.info("native space change with parked window focused id=\(focused.id)")
                    self.navigation.navigate(to: focused.id)
                }
            }
        }
    }

    func stop() {
        managed.restoreParkedWindows()
    }

    func handle(_ event: WindowEvent) {
        guard !screenIsLocked() else {
            Log.engine.debug("window event ignored: the screen is locked")
            return
        }

        windowSystem.duringOperation("window-event") {
            fullScreenReturns.follow()

            switch event {
            case let .created(win):
                enrollment.enroll(win, to: workspaces.current)
            case let .focused(win):
                navigation.follow(win)
            case let .destroyed(windowId):
                if !managed.unmanage(windowId, reason: "destroyed") {
                    navigation.restore()
                }
            case let .minimized(windowId):
                guard workspaces.workspace(for: windowId) != nil else { return }

                for memberId in workspaces.tabGroupMembers(of: windowId) {
                    managed.unmanage(memberId, reason: "minimized")
                }

                navigation.restore()
            case let .unminimized(win):
                for recovered in desktop.recover([win]) {
                    managed.assign(recovered, to: workspaces.current)
                }
            }
        }
    }

    func handle(_ action: Action) {
        switch action {
        case let .switchToWorkspace(workspace): switchToWorkspace(workspace)
        case let .moveWindowToWorkspace(workspace): moveFocusedWindow(toWorkspace: workspace)
        case let .focus(direction): focusWindow(direction)
        case let .moveWindow(step): reframeFocusedWindow(.step(step))
        case .centerWindow: reframeFocusedWindow(.center)
        case .quit: quit()
        case .restart: restart()
        }
    }

    /// Enrolls the windows no workspace knows. Window events are dropped while the screen is
    /// locked, so a window that appeared behind the login window reached no workspace.
    func resync(windows: [WindowSnapshot]) {
        windowSystem.duringOperation("resync") {
            for win in windows {
                managed.assign(win, to: workspaces.current)
            }
        }
    }

    func switchToWorkspace(_ workspace: Int) {
        windowSystem.duringOperation("switch-to-workspace") {
            if let focused = windowSystem.focused(), focused.isFullScreen,
               let previous = workspaces.workspace(for: focused.id) {
                managed.releaseToFullScreen(focused.id, from: previous)
            }

            managed.dropWindowsThatLeftTheDesktop()

            if let focused = windowSystem.focused() {
                managed.assign(focused, to: workspaces.current)
            }

            let onDesktop = managed.isDesktopInFront
            Log.engine.info("switch requested target=\(workspace) current=\(self.workspaces.current) onDesktop=\(onDesktop)")

            if workspace == workspaces.current {
                if !onDesktop {
                    navigation.returnToDesktop()
                }
                return
            }

            managed.switchTo(workspace)

            if onDesktop {
                navigation.restore()
            } else {
                navigation.returnToDesktop()
            }
        }
    }

    func moveFocusedWindow(toWorkspace workspace: Int) {
        windowSystem.duringOperation("move-window-to-workspace") {
            guard workspace >= 1 else {
                Log.engine.info("move dropped: invalid workspace \(workspace)")
                return
            }
            guard let win = windowSystem.focused(), managed.move(win, to: workspace) else {
                Log.engine.info("move to \(workspace) dropped: no valid window to move")
                return
            }

            navigation.restore()
        }
    }

    func focusWindow(_ direction: Direction) {
        windowSystem.duringOperation("focus-direction") {
            guard let reference = navigation.focusedWindowOfCurrentWorkspace() else {
                Log.engine.info("focus \(direction.rawValue) dropped: no reference in workspace \(self.workspaces.current)")
                return
            }

            let candidates = workspaces.windowIds(in: workspaces.current)
                .filter { $0 != reference.id && managed.placement(of: $0) == .active }

            let neighbors = Neighbors(around: reference.frame, among: windowSystem.frames(of: candidates))
            guard let target = neighbors.nearest(to: direction) else {
                Log.engine.info("focus \(direction.rawValue) dropped: no window that way")
                return
            }

            Log.engine.info("focus \(direction.rawValue) from \(reference.logDescription) → id=\(target)")
            _ = desktop.focus(target)
        }
    }

    func reframeFocusedWindow(_ change: FrameChange) {
        windowSystem.duringOperation(change.operation) {
            guard let win = navigation.focusedWindowOfCurrentWorkspace() else {
                Log.engine.info("\(change.logDescription) dropped: no window of workspace \(self.workspaces.current) focused")
                return
            }
            guard managed.placement(of: win.id) == .active else {
                Log.engine.info("\(change.logDescription) dropped: id=\(win.id) is parked")
                return
            }

            Log.engine.info("\(change.logDescription) \(win.logDescription)")
            if !desktop.reframe(win.id, change) {
                managed.unmanage(win.id, reason: "gone")
            }
        }
    }
}

extension Engine {
    static func system(
        desktop: any Desktop,
        windowSystem: WindowSystem,
        workspaces: Workspaces,
        scheduleRetry: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        },
        screenIsLocked: @escaping () -> Bool = { false },
        quit: @escaping () -> Void = {},
        restart: @escaping () -> Void = {}
    ) -> Engine {
        let managed = ManagedWindows(
            desktop: desktop,
            windowSystem: windowSystem,
            workspaces: workspaces,
            parkedWindows: ParkedWindows()
        )
        let enrollment = WindowEnrollment(
            windowSystem: windowSystem,
            workspaces: workspaces,
            managed: managed,
            scheduleRetry: scheduleRetry
        )
        let navigation = Navigation(
            desktop: desktop,
            windowSystem: windowSystem,
            workspaces: workspaces,
            managed: managed,
            enrollment: enrollment
        )
        let fullScreenReturns = FullScreenReturns(
            windowSystem: windowSystem,
            workspaces: workspaces,
            managed: managed,
            navigation: navigation,
            scheduleRetry: scheduleRetry
        )

        return Engine(
            desktop: desktop,
            windowSystem: windowSystem,
            workspaces: workspaces,
            managed: managed,
            enrollment: enrollment,
            navigation: navigation,
            fullScreenReturns: fullScreenReturns,
            screenIsLocked: screenIsLocked,
            quit: quit,
            restart: restart
        )
    }
}
