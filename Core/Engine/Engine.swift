import CoreGraphics
import Foundation

final class Engine {
    private let desktop: any Desktop
    private let windowSystem: WindowSystem
    private let workspaces: Workspaces
    private let placement: WindowPlacement
    private let enrollment: WindowEnrollment
    private let navigation: Navigation
    private let fullScreenReturns: FullScreenReturns
    private let log: LogChannel

    init(
        desktop: any Desktop,
        windowSystem: WindowSystem,
        workspaces: Workspaces,
        placement: WindowPlacement,
        enrollment: WindowEnrollment,
        navigation: Navigation,
        fullScreenReturns: FullScreenReturns,
        log: LogChannel = Log.engine
    ) {
        self.desktop = desktop
        self.windowSystem = windowSystem
        self.workspaces = workspaces
        self.placement = placement
        self.enrollment = enrollment
        self.navigation = navigation
        self.fullScreenReturns = fullScreenReturns
        self.log = log
    }

    func start(windows: [WindowSnapshot], restoring saved: SavedState? = nil) {
        windowSystem.duringOperation("start") {
            placement.restore(windows, from: saved)

            desktop.startWatching { [weak self] event in self?.handle(event) }
        }
    }

    private func handle(_ event: DesktopEvent) {
        switch event {
        case .nativeSpaceChange: followNativeSpaceChange()
        case .screenParametersChange: reparkAfterScreenParametersChange()
        case let .displayChange(change): relocate(change)
        }
    }

    private func relocate(_ change: DisplayChange) {
        windowSystem.duringOperation("display-change") { placement.relocate(change) }
    }

    /// macOS moves windows to their last frame on the display after the first notification of
    /// a plug, so a parked window can be back on screen once the display change is handled.
    private func reparkAfterScreenParametersChange() {
        windowSystem.duringOperation("screen-parameters-change") { desktop.repark(placement.parked) }
    }

    private func followNativeSpaceChange() {
        windowSystem.duringOperation("native-space-change") {
            pinAnchorOnManagedSpace()

            guard let focused = windowSystem.focused(),
                  placement.isParked(focused.id)
            else {
                log.debug("native space change: no parked window focused")
                fullScreenReturns.followWithRetries()
                desktop.repark(placement.parked)
                return
            }

            log.info("native space change with parked window focused id=\(focused.id)")
            navigation.navigate(to: focused.id)
        }
    }

    /// A managed window on screen is what tells the managed Space is in front.
    private func pinAnchorOnManagedSpace() {
        guard windowSystem.showsAny(workspaces.allWindowIds) else { return }

        desktop.pinAnchor()
    }

    /// macOS can move a parked window back on screen after the native space change is
    /// handled, as when a window of the same application leaves full screen.
    private func reparkIfParked(_ windowId: CGWindowID) {
        guard let parkedFrom = placement.parked[windowId] else { return }

        windowSystem.duringOperation("parked-window-reframed") { desktop.repark([windowId: parkedFrom]) }
    }

    func stop() {
        placement.restoreParkedWindows()
    }

    func handle(_ event: WindowEvent) {
        // A resize drag sends a stream of these, and none changes a workspace.
        if case let .reframed(windowId) = event {
            if let windowId { reparkIfParked(windowId) }
            return
        }
        windowSystem.duringOperation("window-event") {
            fullScreenReturns.follow()
            apply(event)
        }
    }

    private func apply(_ event: WindowEvent) {
        switch event {
        case let .created(win):
            enrollment.enroll(win, to: workspaces.current)
        case let .focused(win):
            placement.remember(win)
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
        case .reframed:
            break
        }
    }

    func handle(_ action: Action) {
        switch action {
        case let .switchToWorkspace(workspace): switchToWorkspace(workspace)
        case let .moveWindowToWorkspace(workspace): moveFocusedWindow(toWorkspace: workspace)
        case let .focus(direction): focusWindow(direction)
        case let .moveWindow(direction):
            reframeFocusedWindow(operation: "move-window", keepingMaximized: true) { _ in .move(direction) }
        case let .resize(change):
            reframeFocusedWindow(operation: "resize", keepingMaximized: true) { _ in .resize(change) }
        case .centerWindow: reframeFocusedWindow(operation: "center-window") { _ in .center }
        case .maximize: reframeFocusedWindow(operation: "maximize") { .maximize(restoring: $0) }
        case let .tile(direction): reframeFocusedWindow(operation: "tile") { .tile(direction, restoring: $0) }
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

    var display: Display { desktop.display }

    var activeWindowIds: Set<CGWindowID> {
        workspaces.allWindowIds.filter { !placement.isParked($0) }
    }

    func holds(_ windowId: CGWindowID) -> Bool {
        workspaces.membership(of: windowId) != .unassigned
    }

    func change(to display: Display) {
        desktop.change(to: display)
    }

    /// Lets a window that moved to another display go, for that display's engine to assign.
    func release(_ windowId: CGWindowID) {
        placement.release(windowId)
    }

    /// - Returns: whether a workspace holds the window.
    func assign(_ win: WindowSnapshot) -> Bool {
        placement.assign(win, to: workspaces.current).workspace != nil
    }

    var savedState: SavedState { placement.savedState }

    /// Takes the workspaces, parked windows and original frames of the engine of a removed display.
    func absorb(_ state: SavedState) {
        windowSystem.duringOperation("absorb-display") { placement.absorb(state) }
    }

    func switchToWorkspace(_ workspace: Int) {
        windowSystem.duringOperation("switch-to-workspace") {
            let focused = windowSystem.focused()
            if let focused, focused.isFullScreen, let previous = workspaces.workspace(for: focused.id) {
                placement.releaseToFullScreen(focused.id, from: previous)
            }

            // A tab brought to the front joins its group here, so the tab it hid is not
            // dropped as a window that left the desktop.
            if let focused {
                placement.assign(focused, to: workspaces.current)
            }

            placement.dropWindowsThatLeftTheDesktop()

            let onDesktop = placement.isDesktopInFront
            log.info("switch requested target=\(workspace) current=\(self.workspaces.current) onDesktop=\(onDesktop)")

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
                log.info("move dropped: invalid workspace \(workspace)")
                return
            }
            guard let win = windowSystem.focused(), placement.move(win, to: workspace) else {
                log.info("move to \(workspace) dropped: no valid window to move")
                return
            }

            navigation.restore()
        }
    }

    func focusWindow(_ direction: Direction) {
        windowSystem.duringOperation("focus-direction") {
            guard let reference = navigation.focusedWindowOfCurrentWorkspace() else {
                log.info("focus \(direction.rawValue) dropped: no reference in workspace \(self.workspaces.current)")
                return
            }

            let candidates = workspaces.windowIds(in: workspaces.current)
                .filter { $0 != reference.id && !placement.isParked($0) }

            let frames = windowSystem.frames(of: candidates)
            placement.remember(frames)
            let neighbors = Neighbors(around: reference.frame, among: frames)
            guard let target = neighbors.nearest(to: direction) else {
                log.info("focus \(direction.rawValue) dropped: no window that way")
                return
            }

            log.info("focus \(direction.rawValue) from \(reference.logDescription) → id=\(target)")
            _ = desktop.focus(target)
        }
    }

    /// - Parameter operation: one name per action, so the round-trip cost of a step and of a
    ///   centering are reported separately.
    /// - Parameter keepingMaximized: drops the change when the window fills the screen. The
    ///   window would leave the maximized frame, and the frame it goes back to is dropped
    ///   with it.
    private func reframeFocusedWindow(
        operation: StaticString,
        keepingMaximized: Bool = false,
        _ change: (_ restoring: CGRect?) -> FrameChange
    ) {
        windowSystem.duringOperation(operation) {
            guard let win = navigation.focusedWindowOfCurrentWorkspace() else {
                log.info("\(operation) dropped: no window of workspace \(self.workspaces.current) focused")
                return
            }
            guard !placement.isParked(win.id) else {
                log.info("\(operation) dropped: id=\(win.id) is parked")
                return
            }
            guard !keepingMaximized || !desktop.isMaximized(win.frame) else {
                log.info("\(operation) dropped: id=\(win.id) is maximized")
                return
            }

            placement.reframe(win, change)
        }
    }
}

extension Engine {
    static func system(
        desktop: any Desktop,
        windowSystem: WindowSystem,
        workspaces: Workspaces,
        layouts: DisplayLayouts,
        scheduleRetry: @escaping (TimeInterval, @escaping () -> Void) -> Void = Backoff.onMainQueue,
        log: LogChannel = Log.engine
    ) -> Engine {
        let originalFrames = OriginalFrames(tabs: workspaces.tabGroupMembers(of:))
        let admission = Admission(windowSystem: windowSystem, workspaces: workspaces, log: log)
        let placement = WindowPlacement(
            desktop: desktop,
            windowSystem: windowSystem,
            workspaces: workspaces,
            admission: admission,
            parkedWindows: ParkedWindows(),
            originalFrames: originalFrames,
            layouts: layouts,
            log: log
        )
        let enrollment = WindowEnrollment(
            windowSystem: windowSystem,
            workspaces: workspaces,
            placement: placement,
            scheduleRetry: scheduleRetry
        )
        let navigation = Navigation(
            desktop: desktop,
            windowSystem: windowSystem,
            workspaces: workspaces,
            placement: placement,
            enrollment: enrollment,
            log: log
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
            placement: placement,
            enrollment: enrollment,
            navigation: navigation,
            fullScreenReturns: fullScreenReturns,
            log: log
        )
    }
}
