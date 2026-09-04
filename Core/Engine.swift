import CoreGraphics
import Foundation

final class Engine {
    private let desktop: any Desktop
    private let windowSystem: WindowSystem
    private let workspaces: Workspaces
    private let parkedWindows: ParkedWindows
    private let scheduleRetry: (TimeInterval, @escaping () -> Void) -> Void
    private let screenIsLocked: () -> Bool
    private let quit: () -> Void
    private let restart: () -> Void
    private var expectedNavigation = false

    private static let firstReturnFromFullScreenDelay: TimeInterval = 0.1
    private static let lastReturnFromFullScreenDelay: TimeInterval = 1.6
    private static let firstLateArrivalDelay: TimeInterval = 0.1
    private static let lastLateArrivalDelay: TimeInterval = 0.8

    init(
        desktop: any Desktop,
        windowSystem: WindowSystem,
        workspaces: Workspaces,
        parkedWindows: ParkedWindows,
        scheduleRetry: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        },
        screenIsLocked: @escaping () -> Bool = { false },
        quit: @escaping () -> Void = {},
        restart: @escaping () -> Void = {}
    ) {
        self.desktop = desktop
        self.windowSystem = windowSystem
        self.workspaces = workspaces
        self.parkedWindows = parkedWindows
        self.scheduleRetry = scheduleRetry
        self.screenIsLocked = screenIsLocked
        self.quit = quit
        self.restart = restart
    }

    func start(windows: [WindowSnapshot]) {
        windowSystem.duringOperation("start") {
            for win in desktop.recover(windows) {
                assign(win, to: 1)
            }

            desktop.startWatching { [weak self] in
                guard let self else { return }

                self.windowSystem.duringOperation("native-space-change") {
                    guard let focused = self.windowSystem.focused(),
                          self.parkedWindows.placement(of: focused.id) == .parked
                    else {
                        Log.engine.debug("native space change: no parked window focused")
                        self.followWindowsBackFromFullScreen(retryingIn: Self.firstReturnFromFullScreenDelay)
                        self.desktop.repark(self.parkedWindows.all)
                        return
                    }

                    Log.engine.info("native space change with parked window focused id=\(focused.id)")
                    self.handleManualNavigation(focused.id)
                }
            }
        }
    }

    func stop() {
        let parked = parkedWindows.all.map { (windowId: $0.windowId, placement: Placement.active) }
        Log.engine.info("restoring \(parked.count) parked windows")
        place(parked)
    }

    func handle(_ event: WindowEvent) {
        guard !screenIsLocked() else {
            Log.engine.debug("window event ignored: the screen is locked")
            return
        }

        windowSystem.duringOperation("window-event") {
            followWindowsBackFromFullScreen()

            switch event {
            case let .created(win):
                if assign(win, to: workspaces.current) == nil, win.isAdmissible {
                    adoptLater(win.id, retryingIn: Self.firstLateArrivalDelay)
                }
            case let .focused(win):
                if parkedWindows.placement(of: win.id) == .parked {
                    guard windowSystem.focused()?.id == win.id else {
                        Log.engine.debug("ignoring stale focus event id=\(win.id)")
                        return
                    }
                    handleManualNavigation(win.id)
                    return
                }

                guard canManage(win) else {
                    if win.isAdmissible { adoptLater(win.id, retryingIn: Self.firstLateArrivalDelay) }
                    return
                }

                switch workspaces.membership(of: win, whenNew: workspaces.current) {
                case let .fullScreen(workspace):
                    guard !followBackFromFullScreen(win, to: workspace) else { return }
                    adopt(win, into: workspaces.current)
                case let .assigned(workspace):
                    workspaces.recordFocus(on: win.id, in: workspace)
                case let .unassigned(workspace):
                    adopt(win, into: workspace)
                }
            case let .destroyed(windowId):
                if !unmanage(windowId, reason: "destroyed") {
                    restoreFocus()
                }
            case let .minimized(windowId):
                guard workspaces.workspace(for: windowId) != nil else { return }

                for memberId in workspaces.tabGroupMembers(of: windowId) {
                    unmanage(memberId, reason: "minimized")
                }

                restoreFocus()
            case let .unminimized(win):
                for recovered in desktop.recover([win]) {
                    assign(recovered, to: workspaces.current)
                }
            }
        }
    }

    /// Adopts the windows no workspace knows. Window events are dropped while the screen is
    /// locked, so a window that appeared behind the login window reached no workspace.
    func resync(windows: [WindowSnapshot]) {
        windowSystem.duringOperation("resync") {
            for win in windows where workspaces.workspace(for: win.id) == nil {
                assign(win, to: workspaces.current)
            }
        }
    }

    func handle(_ action: Action) {
        switch action {
        case let .switchToWorkspace(workspace): switchToWorkspace(workspace)
        case let .moveWindowToWorkspace(workspace): moveFocusedWindow(toWorkspace: workspace)
        case let .focus(direction): focusWindow(direction)
        case let .moveWindow(step): moveFocusedWindow(step)
        case .quit: quit()
        case .restart: restart()
        }
    }

    func switchToWorkspace(_ workspace: Int) {
        windowSystem.duringOperation("switch-to-workspace") {
            if let focused = windowSystem.focused(), focused.isFullScreen,
               let previous = workspaces.workspace(for: focused.id) {
                unmanage(focused.id, reason: "fullscreen")
                workspaces.recordFullScreen(focused.id, leaving: previous)
            }

            let parked = workspaces.allWindowIds.filter { parkedWindows.placement(of: $0) == .parked }
            if windowSystem.showsAny(parked) {
                for windowId in workspaces.allWindowIds.subtracting(parked)
                where !windowSystem.showsAny(Set(workspaces.tabGroupMembers(of: windowId))) {
                    guard let snapshot = windowSystem.snapshot(of: windowId), !snapshot.isFullScreen else { continue }
                    unmanage(windowId, reason: "left the desktop")
                }
            }

            if let focused = windowSystem.focused(), workspaces.workspace(for: focused.id) == nil {
                assign(focused, to: workspaces.current)
            }

            let onDesktop = isDesktopInFront
            Log.engine.info("switch requested target=\(workspace) current=\(self.workspaces.current) onDesktop=\(onDesktop)")

            if workspace == workspaces.current {
                if !onDesktop {
                    returnToDesktop()
                }
                return
            }

            transitionToWorkspace(workspace)

            if onDesktop {
                restoreFocus()
            } else {
                returnToDesktop()
            }
        }
    }

    func moveFocusedWindow(toWorkspace workspace: Int) {
        windowSystem.duringOperation("move-window-to-workspace") {
            guard workspace >= 1 else {
                Log.engine.info("move dropped: invalid workspace \(workspace)")
                return
            }
            guard let win = windowSystem.focused(), canManage(win) else {
                Log.engine.info("move to \(workspace) dropped: no valid window to move")
                return
            }

            let placement: Placement = workspace == workspaces.current ? .active : .parked
            Log.engine.info("moving window \(win.logDescription) to workspace \(workspace) placement=\(placement)")
            place(win.id, at: placement)
            workspaces.move(win.id, to: workspace)

            restoreFocus()
        }
    }

    func focusWindow(_ direction: Direction) {
        windowSystem.duringOperation("focus-direction") {
            guard let reference = focusedWindowOfCurrentWorkspace() else {
                Log.engine.info("focus \(direction.rawValue) dropped: no reference in workspace \(self.workspaces.current)")
                return
            }

            let candidates = workspaces.windowIds(in: workspaces.current)
                .filter { $0 != reference.id && parkedWindows.placement(of: $0) == .active }

            let neighbors = Neighbors(around: reference.frame, among: windowSystem.frames(of: candidates))
            guard let target = neighbors.nearest(to: direction) else {
                Log.engine.info("focus \(direction.rawValue) dropped: no window that way")
                return
            }

            Log.engine.info("focus \(direction.rawValue) from \(reference.logDescription) → id=\(target)")
            _ = desktop.focus(target)
        }
    }

    func moveFocusedWindow(_ step: Step) {
        windowSystem.duringOperation("move-window") {
            guard let win = focusedWindowOfCurrentWorkspace() else {
                Log.engine.info("move \(step.direction.rawValue) dropped: no window of workspace \(self.workspaces.current) focused")
                return
            }
            guard parkedWindows.placement(of: win.id) == .active else {
                Log.engine.info("move \(step.direction.rawValue) dropped: id=\(win.id) is parked")
                return
            }

            Log.engine.info("moving \(win.logDescription) \(step.direction.rawValue) by \(step.points)")
            if !desktop.move(win.id, step) {
                unmanage(win.id, reason: "gone")
            }
        }
    }

    /// The focused window when the current workspace holds it, adopted first when no
    /// workspace does. See `adoptLater` for how a live window ends up in no workspace.
    private func focusedWindowOfCurrentWorkspace() -> WindowSnapshot? {
        guard let focused = windowSystem.focused() else { return nil }

        switch workspaces.workspace(for: focused.id) {
        case workspaces.current: return focused
        case nil: return assign(focused, to: workspaces.current) == workspaces.current ? focused : nil
        default: return nil
        }
    }

    /// macOS posts the focus and creation notifications of a new window before the window is
    /// in the on-screen list, so the on-screen check drops both, and no later notification
    /// names the window. The read is repeated for a moment to adopt it once it shows.
    private func adoptLater(_ windowId: CGWindowID, retryingIn delay: TimeInterval) {
        guard delay <= Self.lastLateArrivalDelay else { return }

        scheduleRetry(delay) { [weak self] in
            guard let self else { return }

            self.windowSystem.duringOperation("late-arrival") {
                guard self.workspaces.workspace(for: windowId) == nil,
                      let win = self.windowSystem.snapshot(of: windowId)
                else { return }

                if self.assign(win, to: self.workspaces.current) == nil {
                    self.adoptLater(windowId, retryingIn: delay * 2)
                }
            }
        }
    }

    /// The window can still read as full screen when the Space change announcing its return
    /// arrives, and macOS sends no notification once it settles: the desktop can stay quiet
    /// until the user acts. The check is repeated for a few seconds to catch that.
    private func followWindowsBackFromFullScreen(retryingIn delay: TimeInterval) {
        guard !followWindowsBackFromFullScreen(), !workspaces.fullScreenWindows.isEmpty,
              delay <= Self.lastReturnFromFullScreenDelay
        else { return }

        scheduleRetry(delay) { [weak self] in
            guard let self else { return }

            self.windowSystem.duringOperation("full-screen-return") {
                self.followWindowsBackFromFullScreen(retryingIn: delay * 2)
            }
        }
    }

    /// A window leaving full screen comes back to the desktop without a notification that
    /// names it. The focus event macOS does send can arrive while the window is still in
    /// transition, and it is dropped then, so every later event is another chance to notice
    /// the window is back.
    @discardableResult
    private func followWindowsBackFromFullScreen() -> Bool {
        for (windowId, workspace) in workspaces.fullScreenWindows {
            guard let win = windowSystem.snapshot(of: windowId), canManage(win),
                  followBackFromFullScreen(win, to: workspace)
            else { continue }

            // The window is back, but the focus can sit on a window this switch just parked.
            restoreFocus()
            return true
        }
        return false
    }

    private func followBackFromFullScreen(_ win: WindowSnapshot, to workspace: Int) -> Bool {
        Log.engine.info("\(win.logDescription) is back from full screen → workspace \(workspace)")
        if workspace != workspaces.current {
            transitionToWorkspace(workspace)
        }
        return assign(win, to: workspace) != nil
    }

    private func adopt(_ win: WindowSnapshot, into workspace: Int) {
        guard let assigned = assign(win, to: workspace), assigned != workspaces.current else { return }
        handleManualNavigation(win.id)
    }

    /// - Returns: `true` when the focus is settled without OttoWM: a tab sibling kept it, or
    ///   the window was never managed. macOS moves the focus off a window it destroys, and
    ///   choosing where it goes next is OttoWM's call only for a window it managed: doing it
    ///   for a dialog, or a window of another native Space, pulls the focus into the current
    ///   workspace.
    @discardableResult
    private func unmanage(_ windowId: CGWindowID, reason: String) -> Bool {
        let workspace = workspaces.workspace(for: windowId)
        let from = workspace.map { String($0) } ?? "none"
        Log.engine.info("\(reason) id=\(windowId), dropped from workspace \(from)")

        // Forgetting a parked window leaves it at the hidden edge with nothing left to
        // bring it back.
        if parkedWindows.placement(of: windowId) == .parked {
            place(windowId, at: .active)
        }

        let focusSettled = workspaces.remove(windowId)
        parkedWindows.forget(windowId)
        return focusSettled || workspace == nil
    }

    private func handleManualNavigation(_ windowId: CGWindowID) {
        windowSystem.duringOperation("manual-navigation") {
            if expectedNavigation {
                expectedNavigation = false
                Log.engine.debug("ignoring manual navigation (one-shot)")
                return
            }

            let closed = workspaces.windowIds(in: workspaces.current).filter { candidate in
                guard let snapshot = windowSystem.snapshot(of: candidate) else { return true }
                return !windowSystem.shows(candidate) && !snapshot.isMinimized && !snapshot.isFullScreen
            }
            if !closed.isEmpty {
                var focusSettled = false
                for closedId in closed {
                    focusSettled = unmanage(closedId, reason: "closed") || focusSettled
                }

                if !focusSettled {
                    restoreFocus()
                }
                return
            }

            let target = workspaces.workspace(for: windowId) ?? 1
            Log.engine.info("manual navigation → workspace \(target) window id=\(windowId)")
            transitionToWorkspace(target)
        }
    }

    private func transitionToWorkspace(_ workspace: Int) {
        let focusToKeep = windowSystem.focused().flatMap { canManage($0) ? $0.id : nil }
        let placements = workspaces.switchTo(workspace, leavingFocusOn: focusToKeep)
        Log.engine.info("switching to \(workspace) activating=\(placements.activating) parking=\(placements.parking)")

        let batch = placements.activating.map { (windowId: $0, placement: Placement.active) }
            + placements.parking.map { (windowId: $0, placement: Placement.parked) }
        place(batch).forEach { unmanage($0, reason: "gone") }
    }

    @discardableResult
    private func assign(_ win: WindowSnapshot, to workspace: Int) -> Int? {
        guard canManage(win) else { return nil }

        let assigned = workspaces.assign(win, to: workspace)
        Log.engine.info("assigned \(win.logDescription) → workspace \(assigned)")

        place(win.id, at: assigned == workspaces.current ? .active : .parked)
        return assigned
    }

    private func place(_ windowId: CGWindowID, at placement: Placement) {
        place([(windowId: windowId, placement: placement)])
    }

    @discardableResult
    private func place(_ placements: [(windowId: CGWindowID, placement: Placement)]) -> [CGWindowID] {
        let outcomes = desktop.place(placements.map {
            (windowId: $0.windowId, placement: $0.placement, owedFrame: parkedWindows.owedFrame(of: $0.windowId))
        })
        parkedWindows.record(outcomes)

        return outcomes.compactMap { outcome -> CGWindowID? in
            guard case let .gone(windowId) = outcome else { return nil }
            return windowId
        }
    }

    private func returnToDesktop() {
        guard !restoreFocus() else { return }

        expectedNavigation = true
        Log.engine.debug("returning to desktop, ignoring next manual navigation")

        if let windowId = workspaces.allWindowIds.first(where: { desktop.focus($0) }) {
            Log.engine.debug("brought the desktop to front via id=\(windowId)")
            return
        }
        Log.engine.debug("no live managed window to bring the desktop to front")
    }

    @discardableResult
    private func restoreFocus() -> Bool {
        windowSystem.duringOperation("restore-focus") {
            let currentWorkspace = workspaces.current

            if let osFocused = windowSystem.focused(), canManage(osFocused) {
                switch workspaces.membership(of: osFocused, whenNew: currentWorkspace) {
                case let .fullScreen(workspace):
                    if followBackFromFullScreen(osFocused, to: workspace) { return true }
                case let .assigned(workspace) where workspace == currentWorkspace:
                    workspaces.recordFocus(on: osFocused.id, in: currentWorkspace)
                    return true
                case .unassigned:
                    if assign(osFocused, to: currentWorkspace) == currentWorkspace { return true }
                default:
                    break
                }
            }

            if let windowId = workspaces.nextWindowToFocus, desktop.focus(windowId) {
                return true
            }

            Log.engine.debug("no window to focus in workspace \(currentWorkspace)")
            return false
        }
    }

    private var isDesktopInFront: Bool {
        let managed = workspaces.allWindowIds
        if managed.isEmpty || windowSystem.showsAny(managed) { return true }

        guard let focused = windowSystem.focused(), windowSystem.shows(focused.id) else { return false }
        return workspaces.hasTabGroup(for: focused)
    }

    private func canManage(_ win: WindowSnapshot) -> Bool {
        guard isDesktopInFront else {
            Log.engine.debug("\(win.logDescription) ignored: another native Space is in front")
            return false
        }
        guard win.isAdmissible else {
            Log.engine.debug("\(win.logDescription) ignored: not admissible")
            return false
        }
        guard windowSystem.shows(win.id) else {
            Log.engine.debug("\(win.logDescription) ignored: not on screen")
            return false
        }

        return true
    }
}
