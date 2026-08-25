import CoreGraphics

/// Orchestrates window lifecycle events and hotkey commands, keeping the pure
/// Workspaces model and the physical Desktop in sync.
final class Engine {
    private let desktop: any Desktop
    private let windowSystem: WindowSystem
    private let workspaces: Workspaces
    private let screenIsLocked: () -> Bool
    private let quit: () -> Void
    private let restart: () -> Void
    private var ignoreNextManualNavigation = false
    private var fullscreenWindowOriginalWorkspace: [CGWindowID: Int] = [:]
    /// The window OttoWM last asked for the focus, and the ones it asked for earlier and
    /// replaced while their answer was still on its way. macOS delivers that answer all the
    /// same, by which time a switch may have parked the window, and a focus event naming a
    /// parked window reads exactly like the user reaching for one.
    private var awaitedFocus: CGWindowID?
    private var supersededFocus: Set<CGWindowID> = []

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

    @discardableResult
    func start(windows: [WindowSnapshot]) -> Engine {
        windowSystem.duringOperation {
            for win in desktop.recover(windows) {
                assign(win, to: 1)
            }

            desktop.startWatching { [weak self] windowId in
                self?.handleManualNavigation(windowId)
            }
        }

        return self
    }

    /// OttoWM leaving takes the workspaces with it, and a window parked at the hidden
    /// edge would be stranded there with nothing left to bring it back.
    func stop() {
        desktop.restoreAll()
    }

    func handle(_ event: WindowEvent) {
        // Behind the lock screen every window reads as closed. Acting on that would
        // unmanage the windows and lose the frames parked ones are restored to. Events
        // are dropped until unlock, which resyncs the state.
        guard !screenIsLocked() else {
            Log.engine.debug("window event ignored: the screen is locked")
            return
        }

        windowSystem.duringOperation {
            switch event {
            case let .created(win):
                assign(win, to: workspaces.currentWorkspace)
            case let .focused(win):
                handleFocused(win)
            case let .destroyed(windowId):
                handleDestroyed(windowId)
            case let .minimized(windowId):
                handleMinimized(windowId)
            case let .unminimized(win):
                // A window minimized while parked was unmanaged with its frame left at
                // the corner. Recovering it is only possible now that it is back.
                for recovered in desktop.recover([win]) {
                    assign(recovered, to: workspaces.currentWorkspace)
                }
            }
        }
    }

    func handle(_ action: Action) {
        switch action {
        case let .switchToWorkspace(workspace): switchToWorkspace(workspace)
        case let .moveWindowToWorkspace(workspace): moveFocusedWindow(toWorkspace: workspace)
        case .quit: stop(); quit()
        case .restart: restart()
        }
    }

    func switchToWorkspace(_ workspace: Int) {
        windowSystem.duringOperation {
            dropFocusedWindowIfFullScreen()
            dropWindowsThatLeftTheDesktop()
            admitFocusedWindow()

            let onDesktop = isDesktopInFront
            Log.engine.info("switch requested target=\(workspace) current=\(self.workspaces.currentWorkspace) onDesktop=\(onDesktop)")

            if workspace == workspaces.currentWorkspace {
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

            let placement: Placement = workspace == workspaces.currentWorkspace ? .active : .storage
            Log.engine.info("moving window \(win.logDescription) to workspace \(workspace) placement=\(placement)")
            desktop.place(win.id, at: placement)
            workspaces.move(win.id, to: workspace)
            // An explicit move overrides the workspace a full screen window would
            // otherwise return to.
            fullscreenWindowOriginalWorkspace[win.id] = nil

            restoreFocus()
        }
    }

    private func handleFocused(_ win: WindowSnapshot) {
        let isEcho = supersededFocus.remove(win.id) != nil
        if awaitedFocus == win.id {
            awaitedFocus = nil
            supersededFocus = []
        }

        if desktop.placement(of: win.id) == .storage {
            // Focus notifications are delivered asynchronously, so this one may
            // describe a focus OttoWM caused before the switch that hid the window.
            // Acting on that echo bounces back to the workspace just left, so only the
            // window the OS considers focused right now, and whose focus OttoWM is not
            // still owed an answer for, counts.
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
        // reached it, so follow them there instead of parking it.
        if let assigned = assign(win, to: workspaces.currentWorkspace),
           assigned != workspaces.currentWorkspace {
            handleManualNavigation(win.id)
        }
    }

    private func handleDestroyed(_ windowId: CGWindowID) {
        let focusSettled = unmanage(windowId, reason: "destroyed")

        if !focusSettled {
            restoreFocus()
        }
    }

    /// A minimize takes the whole tab group to the Dock, so every tab goes out of reach at
    /// once. Dropping only the one the notification named would leave its siblings managed
    /// and focusable, and focusing one of those brings the group back up. It also means no
    /// sibling is left to inherit the focus, the way one does when a tab is closed, so
    /// unlike handleDestroyed this always looks for a new window to focus.
    private func handleMinimized(_ windowId: CGWindowID) {
        guard workspaces.workspace(for: windowId) != nil else { return }

        for memberId in workspaces.tabGroupMembers(of: windowId) {
            unmanage(memberId, reason: "minimized")
        }

        restoreFocus()
    }

    /// A window its application never announced is discovered when the focus is read,
    /// which can happen mid switch. It was on screen in the workspace being left, so it
    /// joins that one rather than the one being entered.
    private func admitFocusedWindow() {
        guard let focused = windowSystem.focused(), workspaces.workspace(for: focused.id) == nil else { return }

        assign(focused, to: workspaces.currentWorkspace)
    }

    private func dropFocusedWindowIfFullScreen() {
        guard let focused = windowSystem.focused(), focused.isFullScreen,
              let workspace = workspaces.workspace(for: focused.id)
        else { return }

        // Unlike a minimized or destroyed one, a full screen window returns to the
        // workspace it left rather than the current one. Recorded after unmanaging,
        // which clears every other trace of the window.
        unmanage(focused.id, reason: "fullscreen")
        fullscreenWindowOriginalWorkspace[focused.id] = workspace
    }

    /// The user can drag a managed window onto another native Space.
    private func dropWindowsThatLeftTheDesktop() {
        let parked = workspaces.allWindowIds.filter { desktop.placement(of: $0) == .storage }
        guard windowSystem.showsAny(parked) else { return }

        for windowId in workspaces.allWindowIds.subtracting(parked) where !windowSystem.shows(windowId) {
            // Records the workspace a fullscreen app is owed.
            guard let s = windowSystem.snapshot(of: windowId), !s.isFullScreen else { continue }
            unmanage(windowId, reason: "left the desktop")
        }
    }

    private func followWindowBackFromFullScreen(_ win: WindowSnapshot) -> Bool {
        guard let workspaceBeforeFullscreen = fullscreenWindowOriginalWorkspace[win.id] else { return false }

        Log.engine.info("\(win.logDescription) is back from full screen → workspace \(workspaceBeforeFullscreen)")
        if workspaceBeforeFullscreen != workspaces.currentWorkspace {
            transitionToWorkspace(workspaceBeforeFullscreen)
        }
        return assign(win, to: workspaceBeforeFullscreen) != nil
    }

    /// Takes a window off OttoWM. As a window out of reach cannot be parked and focusing
    /// it would strand the user away from the desktop, so it stops being managed rather
    /// than being flagged. An app that comes back joins the current workspace like a new
    /// window.
    @discardableResult
    private func unmanage(_ windowId: CGWindowID, reason: String) -> Bool {
        let workspace = workspaces.workspace(for: windowId).map { String($0) } ?? "none"
        Log.engine.info("\(reason) id=\(windowId), dropped from workspace \(workspace)")

        let focusSettled = workspaces.remove(windowId)
        desktop.forget(windowId)
        fullscreenWindowOriginalWorkspace[windowId] = nil
        if awaitedFocus == windowId { awaitedFocus = nil }
        supersededFocus.remove(windowId)
        return focusSettled
    }

    /// Focusing a hidden window means the user navigated to it outside OttoWM (Cmd-Tab or
    /// the Dock on the same native Space, Mission Control from another one), so follow
    /// them by switching to that window's workspace.
    private func handleManualNavigation(_ windowId: CGWindowID) {
        windowSystem.duringOperation {
            if ignoreNextManualNavigation {
                ignoreNextManualNavigation = false
                Log.engine.debug("ignoring manual navigation (one-shot)")
                return
            }

            // AX still resolves elements of destroyed windows, so quitting an app or
            // closing the last windows of a workspace emits focus events for them.
            // Without this guard they would read as manual navigation and switch to a
            // workspace with nothing left in it.
            let currentWindowIds = workspaces.windowIds(in: workspaces.currentWorkspace)
            if !currentWindowIds.isEmpty && currentWindowIds.allSatisfy({ id in
                windowSystem.snapshot(of: id).map { !windowSystem.shows(id) && !$0.isMinimized } ?? true
            }) { return }

            let target = workspaces.workspace(for: windowId) ?? 1
            Log.engine.info("manual navigation → workspace \(target) window id=\(windowId)")
            transitionToWorkspace(target)
        }
    }

    private func transitionToWorkspace(_ workspace: Int) {
        let focusToKeep = windowSystem.focused().flatMap { canManage($0) ? $0.id : nil }
        let placements = workspaces.switchTo(workspace, leavingFocusOn: focusToKeep)
        Log.engine.info("switching to \(workspace) toActive=\(placements.toActive) toStorage=\(placements.toStorage)")

        (placements.toActive.filter { !desktop.place($0, at: .active) }
         + placements.toStorage.filter { !desktop.place($0, at: .storage) })
        .forEach({ unmanage($0, reason: "gone")})
    }

    /// Takes the window under management and places it.
    /// - Returns: the workspace the window landed in, or `nil` if it cannot be managed.
    @discardableResult
    private func assign(_ win: WindowSnapshot, to workspace: Int) -> Int? {
        guard canManage(win) else { return nil }

        let workspaceBeforeWindowEnteredFullscreen = fullscreenWindowOriginalWorkspace.removeValue(forKey: win.id) ?? workspace
        let assigned = workspaces.assign(win, to: workspaceBeforeWindowEnteredFullscreen, tabCount: windowSystem.tabCount(of: win.id))
        Log.engine.info("assigned \(win.logDescription) → workspace \(assigned)")

        desktop.place(win.id, at: assigned == workspaces.currentWorkspace ? .active : .storage)
        return assigned
    }

    /// Leaving an unmanaged native Space or full screen window is only possible by
    /// focusing a managed application. When the workspace is empty, focus any managed
    /// window instead.
    private func returnToDesktop() {
        guard !restoreFocus() else { return }

        ignoreNextManualNavigation = true
        Log.engine.debug("returning to desktop, ignoring next manual navigation")

        for windowId in workspaces.allWindowIds {
            if requestFocus(windowId) {
                Log.engine.debug("brought the desktop to front via id=\(windowId)")
                return
            }
        }
        Log.engine.debug("no live managed window to bring the desktop to front")
    }

    @discardableResult
    private func restoreFocus() -> Bool {
        windowSystem.duringOperation {
            let currentWorkspace = workspaces.currentWorkspace

            if let osFocused = windowSystem.focused(), canManage(osFocused) {
                if followWindowBackFromFullScreen(osFocused) { return true }

                let workspace = workspaces.workspace(for: osFocused.id)
                if workspace == currentWorkspace {
                    workspaces.recordFocus(on: osFocused.id, in: currentWorkspace)
                    return true
                }
                // A window that left management while out of reach is back, and joins
                // the current workspace like a new one. Unless its tab group lives
                // elsewhere, in which case it is parked and something else takes focus.
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

        if let awaitedFocus, awaitedFocus != windowId { supersededFocus.insert(awaitedFocus) }
        awaitedFocus = windowId
        return true
    }

    /// The desktop is in front when at least one managed window is on screen: another
    /// native Space, a full screen app or one the user created, shows none of them.
    private var isDesktopInFront: Bool {
        let managed = workspaces.allWindowIds
        return managed.isEmpty || windowSystem.showsAny(managed)
    }

    /// A window on another native Space is on screen too while that Space is the one in
    /// front, so being on screen only tells a window apart from a hidden one once the
    /// desktop is known to be the Space answering.
    private func canManage(_ win: WindowSnapshot) -> Bool {
        guard isDesktopInFront else {
            Log.engine.debug("\(win.logDescription) ignored: another native Space is in front")
            return false
        }
        return win.isAdmissible && windowSystem.shows(win.id)
    }
}
