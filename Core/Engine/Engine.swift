import CoreGraphics
import Foundation

final class Engine {
    private let desktop: any Desktop
    private let windowSystem: WindowSystem
    private let workspaces: Workspaces
    private let admission: Admission
    private let placement: WindowPlacement
    private let restoringFrames: RestoringFrames
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
        admission: Admission,
        placement: WindowPlacement,
        restoringFrames: RestoringFrames,
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
        self.admission = admission
        self.placement = placement
        self.restoringFrames = restoringFrames
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
                placement.assign(win, to: 1)
            }

            desktop.startWatching { [weak self] in
                guard let self else { return }

                self.windowSystem.duringOperation("native-space-change") {
                    guard let focused = self.windowSystem.focused(),
                          self.placement.isParked(focused.id)
                    else {
                        Log.engine.debug("native space change: no parked window focused")
                        self.fullScreenReturns.followWithRetries()
                        self.desktop.repark(self.placement.parked)
                        return
                    }

                    Log.engine.info("native space change with parked window focused id=\(focused.id)")
                    self.navigation.navigate(to: focused.id)
                }
            }
        }
    }

    func stop() {
        placement.restoreParkedWindows()
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
                if !placement.drop(windowId, reason: "destroyed") {
                    navigation.restore()
                }
            case let .minimized(windowId):
                guard workspaces.workspace(for: windowId) != nil else { return }

                for memberId in workspaces.tabGroupMembers(of: windowId) {
                    placement.drop(memberId, reason: "minimized")
                }

                navigation.restore()
            case let .unminimized(win):
                for recovered in desktop.recover([win]) {
                    placement.assign(recovered, to: workspaces.current)
                }
            }
        }
    }

    func handle(_ action: Action) {
        switch action {
        case let .switchToWorkspace(workspace): switchToWorkspace(workspace)
        case let .moveWindowToWorkspace(workspace): moveFocusedWindow(toWorkspace: workspace)
        case let .focus(direction): focusWindow(direction)
        case let .moveWindow(step): reframeFocusedWindow(operation: "move-window") { _ in .step(step) }
        case .centerWindow: reframeFocusedWindow(operation: "center-window") { _ in .center }
        case .toggleMaximize:
            reframeFocusedWindow(operation: "toggle-maximize") {
                .maximize(restoring: self.restoringFrames.restoringFrame(of: $0.id))
            }
        case let .fill(direction):
            reframeFocusedWindow(operation: "fill") {
                .fill(direction, restoring: self.restoringFrames.restoringFrame(of: $0.id))
            }
        case .quit: quit()
        case .restart: restart()
        }
    }

    /// Enrolls the windows no workspace knows. Window events are dropped while the screen is
    /// locked, so a window that appeared behind the login window reached no workspace.
    func resync(windows: [WindowSnapshot]) {
        windowSystem.duringOperation("resync") {
            for win in windows {
                placement.assign(win, to: workspaces.current)
            }
        }
    }

    func switchToWorkspace(_ workspace: Int) {
        windowSystem.duringOperation("switch-to-workspace") {
            if let focused = windowSystem.focused(), focused.isFullScreen,
               let previous = workspaces.workspace(for: focused.id) {
                placement.releaseToFullScreen(focused.id, from: previous)
            }

            placement.dropWindowsThatLeftTheDesktop()

            if let focused = windowSystem.focused() {
                placement.assign(focused, to: workspaces.current)
            }

            let onDesktop = admission.isDesktopInFront
            Log.engine.info("switch requested target=\(workspace) current=\(self.workspaces.current) onDesktop=\(onDesktop)")

            if workspace == workspaces.current {
                if !onDesktop {
                    navigation.returnToDesktop()
                }
                return
            }

            placement.switchTo(workspace)

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
            guard let win = windowSystem.focused(), placement.move(win, to: workspace) else {
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
                .filter { $0 != reference.id && !placement.isParked($0) }

            let neighbors = Neighbors(around: reference.frame, among: windowSystem.frames(of: candidates))
            guard let target = neighbors.nearest(to: direction) else {
                Log.engine.info("focus \(direction.rawValue) dropped: no window that way")
                return
            }

            Log.engine.info("focus \(direction.rawValue) from \(reference.logDescription) → id=\(target)")
            _ = desktop.focus(target)
        }
    }

    /// - Parameter operation: one name per action, so the round-trip cost of a step and of a
    ///   centering are reported separately.
    /// - Parameter change: takes the window it applies to, which is known only once the
    ///   guards below have passed.
    private func reframeFocusedWindow(operation: StaticString, _ change: (WindowSnapshot) -> FrameChange) {
        windowSystem.duringOperation(operation) {
            guard let win = navigation.focusedWindowOfCurrentWorkspace() else {
                Log.engine.info("\(operation) dropped: no window of workspace \(self.workspaces.current) focused")
                return
            }
            guard !placement.isParked(win.id) else {
                Log.engine.info("\(operation) dropped: id=\(win.id) is parked")
                return
            }

            let requested = change(win)
            Log.engine.info("\(requested.logDescription) \(win.logDescription)")

            let outcomes = desktop.reframe([(windowId: win.id, change: requested)])
            restoringFrames.record(outcomes)
            if outcomes.contains(.gone(win.id)) {
                placement.drop(win.id, reason: "gone")
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
        let restoringFrames = RestoringFrames(tabs: workspaces.tabGroupMembers(of:))
        let admission = Admission(windowSystem: windowSystem, workspaces: workspaces)
        let placement = WindowPlacement(
            desktop: desktop,
            windowSystem: windowSystem,
            workspaces: workspaces,
            admission: admission,
            parkedWindows: ParkedWindows(),
            restoringFrames: restoringFrames
        )
        let enrollment = WindowEnrollment(
            windowSystem: windowSystem,
            workspaces: workspaces,
            admission: admission,
            placement: placement,
            scheduleRetry: scheduleRetry
        )
        let navigation = Navigation(
            desktop: desktop,
            windowSystem: windowSystem,
            workspaces: workspaces,
            placement: placement,
            enrollment: enrollment
        )
        let fullScreenReturns = FullScreenReturns(
            windowSystem: windowSystem,
            workspaces: workspaces,
            placement: placement,
            navigation: navigation,
            scheduleRetry: scheduleRetry
        )

        return Engine(
            desktop: desktop,
            windowSystem: windowSystem,
            workspaces: workspaces,
            admission: admission,
            placement: placement,
            restoringFrames: restoringFrames,
            enrollment: enrollment,
            navigation: navigation,
            fullScreenReturns: fullScreenReturns,
            screenIsLocked: screenIsLocked,
            quit: quit,
            restart: restart
        )
    }
}
