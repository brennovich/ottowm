import CoreGraphics

// Orchestrates windows lifecycle events and hotkey commands, keeping the pure
// Workspaces model and the physical Desktop in sync.
final class Engine {
    private let desktop: any Desktop
    private let screen: Screen
    private let workspaces: Workspaces
    private let screenIsLocked: () -> Bool
    private var ignoreNextManualNavigation = false
    private var fullscreenWindowOriginalWorkspace: [CGWindowID: Int] = [:]

    init(
        desktop: any Desktop,
        screen: Screen,
        workspaces: Workspaces = Workspaces(),
        screenIsLocked: @escaping () -> Bool = { false }
    ) {
        self.desktop = desktop
        self.screen = screen
        self.workspaces = workspaces
        self.screenIsLocked = screenIsLocked
    }

    @discardableResult
    func start(windows: [WindowSnapshot]) -> Engine {
        screen.duringOperation {
            for win in desktop.recover(windows: windows) {
                assignWindowToWorkspace(win, 1)
            }

            desktop.startWatchingForManualNavigation { [weak self] windowId in
                self?.handleManualNavigation(windowId)
            }
        }

        return self
    }

    func handle(_ event: WindowEvent) {
        // A locked screen answers for every window the way a closed one does, and the
        // model would take that literally: windows unmanaged and, worse, the frames the
        // parked ones are owed forgotten. Nothing said while the screen is covered is
        // worth believing, and whatever really happened is swept up on unlock.
        guard !screenIsLocked() else {
            Log.engine.debug("window event ignored: the screen is locked")
            return
        }

        screen.duringOperation {
            switch event {
            case let .created(win):
                assignWindowToWorkspace(win, workspaces.currentWorkspace)
            case let .focused(win):
                handleFocused(win)
            case let .destroyed(windowId):
                handleDestroyed(windowId)
            case let .minimized(windowId):
                handleMinimized(windowId)
            case let .unminimized(win):
                // A window minimized while parked was forgotten where it stood, in the
                // corner: unmanageable then, recoverable only now that it is back.
                for recovered in desktop.recover(windows: [win]) {
                    assignWindowToWorkspace(recovered, workspaces.currentWorkspace)
                }
            }
        }
    }

    func handle(_ action: Action) {
        switch action {
        case let .switchToWorkspace(workspace): switchToWorkspace(workspace)
        case let .moveWindowToWorkspace(workspace): moveFocusedWindow(toWorkspace: workspace)
        }
    }

    func switchToWorkspace(_ workspace: Int) {
        screen.duringOperation {
            dropFocusedWindowIfFullScreen()
            admitFocusedWindow()

            // The desktop is in front when at least one window we manage is on screen:
            // a native Space showing something else (a full screen app) shows none of them.
            let managed = workspaces.allWindowIds
            let onDesktop = managed.isEmpty || screen.showsAny(managed)
            Log.engine.info("switch requested target=\(workspace) current=\(self.workspaces.currentWorkspace) onDesktop=\(onDesktop)")

            if workspace == workspaces.currentWorkspace {
                if !onDesktop {
                    returnToDesktop()
                }
                return
            }

            transitionToWorkspace(workspace)

            if onDesktop {
                restoreWindowsFocusForWorkspace()
            } else {
                returnToDesktop()
            }
        }
    }

    func moveFocusedWindow(toWorkspace workspace: Int) {
        screen.duringOperation {
            guard workspace >= 1 else {
                Log.engine.info("move dropped: invalid workspace \(workspace)")
                return
            }
            guard let win = screen.focused(), isValidWindow(win) else {
                Log.engine.info("move to \(workspace) dropped: no valid window to move")
                return
            }

            let placement: Placement = workspace == workspaces.currentWorkspace ? .active : .storage
            Log.engine.info("moving window \(win.logDescription) to workspace \(workspace) placement=\(placement)")
            desktop.place(win.id, placement)
            workspaces.moveWindowToWorkspace(win.id, workspace)
            // Said out loud, this is where the window belongs from now on, whatever it
            // was owed for having gone full screen.
            fullscreenWindowOriginalWorkspace[win.id] = nil

            restoreWindowsFocusForWorkspace()
        }
    }

    private func handleFocused(_ win: WindowSnapshot) {
        if desktop.placement(of: win.id) == .storage {
            // Focus notifications are delivered asynchronously, so this one may
            // describe a focus OttoWM itself caused before the switch that hid the
            // window. Acting on such an echo bounces straight back to the workspace we
            // just left. Only the window the OS considers focused right now counts.
            guard screen.focused()?.id == win.id else {
                Log.engine.debug("ignoring stale focus event id=\(win.id)")
                return
            }
            handleManualNavigation(win.id)
            return
        }

        guard isValidWindow(win) else { return }

        if followWindowBackFromFullScreen(win) { return }

        if let workspace = workspaces.workspace(for: win.id) {
            workspaces.saveFocusedWindowInWorkspace(workspace, win.id)
            return
        }

        // A tab discovered only now can belong to a group living in another workspace. The
        // user reached it, so follow them there instead of parking it under their nose.
        if let assigned = assignWindowToWorkspace(win, workspaces.currentWorkspace),
           assigned != workspaces.currentWorkspace {
            handleManualNavigation(win.id)
        }
    }

    private func handleDestroyed(_ windowId: CGWindowID) {
        let focusSettled = unmanage(windowId, "destroyed")

        if !focusSettled {
            restoreWindowsFocusForWorkspace()
        }
    }

    private func handleMinimized(_ windowId: CGWindowID) {
        guard workspaces.workspace(for: windowId) != nil else { return }

        unmanage(windowId, "minimized")

        restoreWindowsFocusForWorkspace()
    }

    // A window its application never announced is discovered when the focus is read,
    // which can be in the middle of a switch. It was on screen in the workspace being
    // left, so it joins that one rather than the one being entered.
    private func admitFocusedWindow() {
        guard let focused = screen.focused(), workspaces.workspace(for: focused.id) == nil else { return }

        assignWindowToWorkspace(focused, workspaces.currentWorkspace)
    }

    private func dropFocusedWindowIfFullScreen() {
        guard let focused = screen.focused(), focused.isFullScreen,
              let workspace = workspaces.workspace(for: focused.id)
        else { return }

        // Unlike a minimized or destroyed one, a full screen window has a home to come
        // back to: the workspace it left, not whichever one happens to be current when it
        // returns. Kept aside after unmanaging, which is what wipes the window's slate.
        unmanage(focused.id, "fullscreen")
        fullscreenWindowOriginalWorkspace[focused.id] = workspace
    }

    private func followWindowBackFromFullScreen(_ win: WindowSnapshot) -> Bool {
        guard let workspaceBeforeFullscreen = fullscreenWindowOriginalWorkspace[win.id] else { return false }

        Log.engine.info("\(win.logDescription) is back from full screen → workspace \(workspaceBeforeFullscreen)")
        if workspaceBeforeFullscreen != workspaces.currentWorkspace {
            transitionToWorkspace(workspaceBeforeFullscreen)
        }
        return assignWindowToWorkspace(win, workspaceBeforeFullscreen) != nil
    }

    // A window out of reach cannot be parked, and focusing it would strand the user
    // away from the desktop: a minimized one is off screen, a full screen one owns its
    // own native space, a destroyed one is gone for good. It stops being managed
    // rather than being flagged, and a window that comes back joins whatever workspace
    // is current, like a brand new one.
    @discardableResult
    private func unmanage(_ windowId: CGWindowID, _ reason: String) -> Bool {
        let workspace = workspaces.workspace(for: windowId).map { String($0) } ?? "none"
        Log.engine.info("\(reason) id=\(windowId), dropped from workspace \(workspace)")

        let focusSettled = workspaces.unregisterWindowById(windowId)
        desktop.forget(windowId)
        fullscreenWindowOriginalWorkspace[windowId] = nil
        return focusSettled
    }

    // Focusing a hidden window means the user navigated to it behind OttoWM's back
    // (Cmd-Tab/Dock on the same native Space, or Mission Control from another one),
    // so follow them by switching to that window's workspace.
    private func handleManualNavigation(_ windowId: CGWindowID) {
        screen.duringOperation {
            if ignoreNextManualNavigation {
                ignoreNextManualNavigation = false
                Log.engine.debug("ignoring manual navigation (one-shot)")
                return
            }

            // AX still resolves elements of windows that are already destroyed, so quitting an app,
            // or closing the last windows of a workspace, emits focus events for dying windows.
            // Without the guard, those events would be read as manual navigation and send the user
            // to a workspace whose contents no longer exist.
            let currentWindowIds = workspaces.windowIds(in: workspaces.currentWorkspace)
            if !currentWindowIds.isEmpty && currentWindowIds.allSatisfy({ id in
                screen.snapshot(of: id).map { !screen.shows(id) && !$0.isMinimized } ?? true
            }) { return }

            let target = workspaces.workspace(for: windowId) ?? 1
            Log.engine.info("manual navigation → workspace \(target) window id=\(windowId)")
            transitionToWorkspace(target)
        }
    }

    private func transitionToWorkspace(_ workspace: Int) {
        let focusToKeep = screen.focused().flatMap { isValidWindow($0) ? $0.id : nil }
        let placements = workspaces.switchTo(workspace, leavingFocusOn: focusToKeep)
        Log.engine.info("switching to \(workspace) toActive=\(placements.toActive) toStorage=\(placements.toStorage)")

        (placements.toActive.filter { !desktop.place($0, .active) }
         + placements.toStorage.filter { !desktop.place($0, .storage) })
        .forEach({ unmanage($0, "gone")})
    }

    // Returns the workspace the window landed in.
    @discardableResult
    private func assignWindowToWorkspace(_ win: WindowSnapshot, _ workspace: Int) -> Int? {
        guard isValidWindow(win) else { return nil }

        let workspaceBeforeWindowEnteredFullscreen = fullscreenWindowOriginalWorkspace.removeValue(forKey: win.id) ?? workspace
        let assigned = workspaces.assignWindowToWorkspace(win, workspaceBeforeWindowEnteredFullscreen, tabCount: screen.tabCount(of: win.id))
        Log.engine.info("assigned \(win.logDescription) → workspace \(assigned)")

        desktop.place(win.id, assigned == workspaces.currentWorkspace ? .active : .storage)
        return assigned
    }

    // Coming back from a unmanaged native space/fullscreen is only possible by focusing
    // a managed application. When the workspace is empty our last resort is to bring any
    // managed window to focus.
    private func returnToDesktop() {
        guard !restoreWindowsFocusForWorkspace() else { return }

        ignoreNextManualNavigation = true
        Log.engine.debug("returning to desktop, ignoring next manual navigation")

        for windowId in workspaces.allWindowIds {
            if desktop.focus(windowId) {
                Log.engine.debug("brought the desktop to front via id=\(windowId)")
                return
            }
        }
        Log.engine.debug("no live managed window to bring the desktop to front")
    }

    @discardableResult
    private func restoreWindowsFocusForWorkspace() -> Bool {
        screen.duringOperation {
            let currentWorkspace = workspaces.currentWorkspace

            if let osFocused = screen.focused(), isValidWindow(osFocused) {
                if followWindowBackFromFullScreen(osFocused) { return true }

                let workspace = workspaces.workspace(for: osFocused.id)
                if workspace == currentWorkspace {
                    workspaces.saveFocusedWindowInWorkspace(currentWorkspace, osFocused.id)
                    return true
                }
                // A window that left management while it was out of reach is back. It joins the
                // workspace the user is on now, like a newly created one. Unless it belongs to
                // a tab group that lives elsewhere, in which case it is parked and something
                // else has to take the focus.
                if workspace == nil,
                   assignWindowToWorkspace(osFocused, currentWorkspace) == currentWorkspace {
                    return true
                }
            }

            if let windowId = workspaces.nextWindowToFocus(), desktop.focus(windowId) {
                return true
            }

            Log.engine.debug("no window to focus in workspace \(currentWorkspace)")
            return false
        }
    }

    private func isValidWindow(_ win: WindowSnapshot) -> Bool {
        win.isAdmissible && screen.shows(win.id)
    }
}
