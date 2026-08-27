import CoreGraphics

/// Turns window events and hotkey actions into updates of the `Workspaces` model and
/// moves on the `Desktop`.
final class Engine {
    private let desktop: any Desktop
    private let windowSystem: WindowSystem
    private let workspaces: Workspaces
    private let screenIsLocked: () -> Bool
    private let quit: () -> Void
    private let restart: () -> Void
    private var ignoreNextManualNavigation = false
    private var workspaceBeforeFullScreen = WorkspaceBeforeFullScreen()
    private var awaitedFocus = AwaitedFocus()

    init(
        desktop: any Desktop,
        windowSystem: WindowSystem,
        workspaces: Workspaces = Workspaces(),
        screenIsLocked: @escaping () -> Bool = { false },
        quit: @escaping () -> Void = {},
        restart: @escaping () -> Void = {}
    ) {
        self.desktop = desktop
        self.windowSystem = windowSystem
        self.workspaces = workspaces
        self.screenIsLocked = screenIsLocked
        self.quit = quit
        self.restart = restart
    }

    func start(windows: [WindowSnapshot]) {
        windowSystem.duringOperation {
            for win in desktop.recover(windows) {
                assign(win, to: 1)
            }

            desktop.startWatching { [weak self] windowId in
                self?.handleManualNavigation(windowId)
            }
        }
    }

    /// Prevents lost windows when OttoWM quit or crash.
    func stop() {
        desktop.restoreAll()
    }

    func handle(_ event: WindowEvent) {
        // Behind the lock screen every window reads as closed. Acting on that would drop
        // every window and lose the frames the parked ones are restored to. Events are
        // ignored until the screen unlocks.
        guard !screenIsLocked() else {
            Log.engine.debug("window event ignored: the screen is locked")
            return
        }

        windowSystem.duringOperation {
            switch event {
            case let .created(win):
                assign(win, to: workspaces.current)
            case let .focused(win):
                handleFocused(win)
            case let .destroyed(windowId):
                handleDestroyed(windowId)
            case let .minimized(windowId):
                handleMinimized(windowId)
            case let .unminimized(win):
                // A window minimized while parked was dropped with its frame left at the
                // corner. It can only be recovered now that it is back.
                for recovered in desktop.recover([win]) {
                    assign(recovered, to: workspaces.current)
                }
            }
        }
    }

    func handle(_ action: Action) {
        switch action {
        case let .switchToWorkspace(workspace): switchToWorkspace(workspace)
        case let .moveWindowToWorkspace(workspace): moveFocusedWindow(toWorkspace: workspace)
        case let .focus(direction): focusWindow(direction)
        case .quit: quit()
        case .restart: restart()
        }
    }

    func switchToWorkspace(_ workspace: Int) {
        windowSystem.duringOperation {
            dropFocusedWindowIfFullScreen()
            dropWindowsThatLeftTheDesktop()
            admitFocusedWindow()

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
        windowSystem.duringOperation {
            guard workspace >= 1 else {
                Log.engine.info("move dropped: invalid workspace \(workspace)")
                return
            }
            guard let win = windowSystem.focused(), canManage(win) else {
                Log.engine.info("move to \(workspace) dropped: no valid window to move")
                return
            }

            let placement: Placement = workspace == workspaces.current ? .active : .storage
            Log.engine.info("moving window \(win.logDescription) to workspace \(workspace) placement=\(placement)")
            desktop.place(win.id, at: placement)
            workspaces.move(win.id, to: workspace)
            // An explicit move overrides the workspace a full screen window would
            // otherwise return to.
            workspaceBeforeFullScreen.take(win.id)

            restoreFocus()
        }
    }

    /// Moves the focus to the window `direction` leads to, taking the focused window as the point
    /// of reference.
    func focusWindow(_ direction: Direction) {
        windowSystem.duringOperation {
            guard let reference = windowSystem.focused(),
                  workspaces.workspace(for: reference.id) == workspaces.current
            else {
                Log.engine.info("focus \(direction.rawValue) dropped: no reference in workspace \(self.workspaces.current)")
                return
            }

            let neighbors = Neighbors(around: reference.frame, among: framesAround(reference.id))
            guard let target = neighbors.nearest(to: direction) else {
                Log.engine.info("focus \(direction.rawValue) dropped: no window that way")
                return
            }

            Log.engine.info("focus \(direction.rawValue) from \(reference.logDescription) → id=\(target)")
            requestFocus(target)
        }
    }

    /// The frames a focus move can land on: the windows of the current workspace that are on
    /// screen. A parked window is left out, and so are the ones the on-screen list does not hold:
    /// a window that left the desktop, and the tabs of a group macOS is not showing.
    private func framesAround(_ referenceId: CGWindowID) -> [CGWindowID: CGRect] {
        workspaces.windowIds(in: workspaces.current)
            .filter { $0 != referenceId && desktop.placement(of: $0) == .active && windowSystem.shows($0) }
            .reduce(into: [:]) { frames, windowId in
                guard let frame = windowSystem.snapshot(of: windowId)?.frame else { return }

                frames[windowId] = frame
            }
    }

    private func handleFocused(_ win: WindowSnapshot) {
        let isEcho = awaitedFocus.settle(win.id)

        if desktop.placement(of: win.id) == .storage {
            // Focus notifications arrive asynchronously, so this one may answer a focus
            // OttoWM requested before the switch that parked the window. Acting on it
            // would switch straight back to the workspace just left. Only a window the OS
            // reports as focused right now, by a notification that is not a late answer,
            // counts.
            guard windowSystem.focused()?.id == win.id, !isEcho else {
                Log.engine.debug("ignoring stale focus event id=\(win.id)")
                return
            }
            handleManualNavigation(win.id)
            return
        }

        guard canManage(win) else { return }

        if followWindowBackFromFullScreen(win) { return }

        if let workspace = workspaces.workspace(for: win.id) {
            workspaces.recordFocus(on: win.id, in: workspace)
            return
        }

        // A tab discovered only now can belong to a group in another workspace. The user
        // focused it, so switch there instead of parking it.
        if let assigned = assign(win, to: workspaces.current),
           assigned != workspaces.current {
            handleManualNavigation(win.id)
        }
    }

    private func handleDestroyed(_ windowId: CGWindowID) {
        let focusSettled = unmanage(windowId, reason: "destroyed")

        if !focusSettled {
            restoreFocus()
        }
    }

    /// macOS minimizes a whole tab group, so every member goes out of reach at once.
    /// Dropping only the window the notification names would leave its siblings managed and
    /// focusable, and focusing one of those restores the group. No sibling keeps the focus,
    /// unlike a closed tab, so this always picks a new window to focus.
    private func handleMinimized(_ windowId: CGWindowID) {
        guard workspaces.workspace(for: windowId) != nil else { return }

        for memberId in workspaces.tabGroupMembers(of: windowId) {
            unmanage(memberId, reason: "minimized")
        }

        restoreFocus()
    }

    /// A window its application never announced is found when the focus is read, which can
    /// happen during a switch. It was on screen in the workspace being left, so it joins
    /// that one.
    private func admitFocusedWindow() {
        guard let focused = windowSystem.focused(), workspaces.workspace(for: focused.id) == nil else { return }

        assign(focused, to: workspaces.current)
    }

    private func dropFocusedWindowIfFullScreen() {
        guard let focused = windowSystem.focused(), focused.isFullScreen,
              let workspace = workspaces.workspace(for: focused.id)
        else { return }

        // Recorded after the window is dropped, because dropping it clears every other
        // trace of it.
        unmanage(focused.id, reason: "fullscreen")
        workspaceBeforeFullScreen.record(focused.id, in: workspace)
    }

    /// The user can drag a managed window onto another native Space.
    private func dropWindowsThatLeftTheDesktop() {
        let parked = workspaces.allWindowIds.filter { desktop.placement(of: $0) == .storage }
        guard windowSystem.showsAny(parked) else { return }

        for windowId in workspaces.allWindowIds.subtracting(parked) where !windowSystem.shows(windowId) {
            // A full screen window is off the desktop but comes back to it, so it stays
            // managed. A window `KnownWindows` can no longer resolve is skipped here too, and
            // dropped by the next place() that cannot reach it.
            guard let snapshot = windowSystem.snapshot(of: windowId), !snapshot.isFullScreen else { continue }
            unmanage(windowId, reason: "left the desktop")
        }
    }

    private func followWindowBackFromFullScreen(_ win: WindowSnapshot) -> Bool {
        guard let workspace = workspaceBeforeFullScreen.workspace(of: win.id) else { return false }

        Log.engine.info("\(win.logDescription) is back from full screen → workspace \(workspace)")
        if workspace != workspaces.current {
            transitionToWorkspace(workspace)
        }
        return assign(win, to: workspace) != nil
    }

    /// Drops the window from OttoWM. A window out of reach cannot be parked, and focusing
    /// it would leave the user on another native Space, so it is dropped rather than
    /// marked. It joins the current workspace like a new window if it comes back.
    @discardableResult
    private func unmanage(_ windowId: CGWindowID, reason: String) -> Bool {
        let workspace = workspaces.workspace(for: windowId).map { String($0) } ?? "none"
        Log.engine.info("\(reason) id=\(windowId), dropped from workspace \(workspace)")

        let focusSettled = workspaces.remove(windowId)
        desktop.forget(windowId)
        workspaceBeforeFullScreen.take(windowId)
        awaitedFocus.forget(windowId)
        return focusSettled
    }

    /// A parked window taking the focus means the user reached it outside OttoWM: Cmd-Tab
    /// or the Dock on the same native Space, Mission Control from another one. Switches to
    /// that window's workspace.
    private func handleManualNavigation(_ windowId: CGWindowID) {
        windowSystem.duringOperation {
            if ignoreNextManualNavigation {
                ignoreNextManualNavigation = false
                Log.engine.debug("ignoring manual navigation (one-shot)")
                return
            }

            if currentWorkspaceIsClosing { return }

            let target = workspaces.workspace(for: windowId) ?? 1
            Log.engine.info("manual navigation → workspace \(target) window id=\(windowId)")
            transitionToWorkspace(target)
        }
    }

    /// Whether every window of the current workspace is already gone.
    ///
    /// AX still resolves the elements of destroyed windows, so quitting an application or
    /// closing the last windows of a workspace emits focus events for them. Those events
    /// would otherwise read as manual navigation, and switch to a workspace with nothing
    /// left in it.
    private var currentWorkspaceIsClosing: Bool {
        let windowIds = workspaces.windowIds(in: workspaces.current)
        guard !windowIds.isEmpty else { return false }

        return windowIds.allSatisfy { windowId in
            windowSystem.snapshot(of: windowId).map { !windowSystem.shows(windowId) && !$0.isMinimized } ?? true
        }
    }

    private func transitionToWorkspace(_ workspace: Int) {
        let focusToKeep = windowSystem.focused().flatMap { canManage($0) ? $0.id : nil }
        let placements = workspaces.switchTo(workspace, leavingFocusOn: focusToKeep)
        Log.engine.info("switching to \(workspace) toActive=\(placements.toActive) toStorage=\(placements.toStorage)")

        (placements.toActive.filter { !desktop.place($0, at: .active) }
         + placements.toStorage.filter { !desktop.place($0, at: .storage) })
            .forEach { unmanage($0, reason: "gone") }
    }

    /// Takes the window under management and places it.
    /// - Returns: the workspace the window landed in, or `nil` if it cannot be managed.
    @discardableResult
    private func assign(_ win: WindowSnapshot, to workspace: Int) -> Int? {
        guard canManage(win) else { return nil }

        let target = workspaceBeforeFullScreen.take(win.id) ?? workspace
        let assigned = workspaces.assign(win, to: target, tabCount: windowSystem.tabCount(of: win.id))
        Log.engine.info("assigned \(win.logDescription) → workspace \(assigned)")

        desktop.place(win.id, at: assigned == workspaces.current ? .active : .storage)
        return assigned
    }

    /// Focusing a managed window is the only way back from another native Space or from a
    /// full screen window. Falls back to any managed window when the current workspace is
    /// empty.
    private func returnToDesktop() {
        guard !restoreFocus() else { return }

        ignoreNextManualNavigation = true
        Log.engine.debug("returning to desktop, ignoring next manual navigation")

        if let windowId = workspaces.allWindowIds.first(where: { requestFocus($0) }) {
            Log.engine.debug("brought the desktop to front via id=\(windowId)")
            return
        }
        Log.engine.debug("no live managed window to bring the desktop to front")
    }

    @discardableResult
    private func restoreFocus() -> Bool {
        windowSystem.duringOperation {
            let currentWorkspace = workspaces.current

            if let osFocused = windowSystem.focused(), canManage(osFocused) {
                if followWindowBackFromFullScreen(osFocused) { return true }

                let workspace = workspaces.workspace(for: osFocused.id)
                if workspace == currentWorkspace {
                    workspaces.recordFocus(on: osFocused.id, in: currentWorkspace)
                    return true
                }
                // A window dropped while out of reach is back, and joins the current
                // workspace like a new one. If its tab group lives elsewhere it is parked
                // instead, and another window takes the focus.
                if workspace == nil,
                   assign(osFocused, to: currentWorkspace) == currentWorkspace {
                    return true
                }
            }

            if let windowId = workspaces.nextWindowToFocus, requestFocus(windowId) {
                return true
            }

            Log.engine.debug("no window to focus in workspace \(currentWorkspace)")
            return false
        }
    }

    private func requestFocus(_ windowId: CGWindowID) -> Bool {
        guard desktop.focus(windowId) else { return false }

        awaitedFocus.request(windowId)
        return true
    }

    /// True when at least one managed window is on screen. Another native Space or a full
    /// screen window shows none of them.
    private var isDesktopInFront: Bool {
        let managed = workspaces.allWindowIds
        return managed.isEmpty || windowSystem.showsAny(managed)
    }

    /// The on-screen list covers whichever native Space is in front, so it tells a managed
    /// window apart from a parked one only once the desktop is known to be that Space.
    private func canManage(_ win: WindowSnapshot) -> Bool {
        guard isDesktopInFront else {
            Log.engine.debug("\(win.logDescription) ignored: another native Space is in front")
            return false
        }
        return win.isAdmissible && windowSystem.shows(win.id)
    }
}
