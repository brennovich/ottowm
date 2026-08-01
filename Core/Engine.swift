import CoreGraphics

// Orchestrates windows lifecycle events and hotkey commands, keeping the pure
// Workspaces model and the physical Desktop in sync.
final class Engine {
    private let desktop: any Desktop
    private let screen: Screen
    private let workspaces: Workspaces
    private var ignoreNextManualNavigation = false

    init(
        desktop: any Desktop,
        screen: Screen,
        workspaces: Workspaces = Workspaces()
    ) {
        self.desktop = desktop
        self.screen = screen
        self.workspaces = workspaces
    }

    func start(windows: [WindowSnapshot]) {
        screen.duringOperation("start") {
            desktop.recover(windows: windows)

            for win in windows {
                assignWindowToWorkspace(win, 1)
            }

            desktop.startWatchingForManualNavigation { [weak self] windowId in
                self?.handleManualNavigation(windowId)
            }
        }
    }

    func handle(_ event: WindowEvent) {
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
                desktop.recover(windows: [win])
                assignWindowToWorkspace(win, workspaces.currentWorkspace)
            }
        }
    }

    func switchToWorkspace(_ workspace: Int) {
        screen.duringOperation("switchToWorkspace(\(workspace))") {
            dropFocusedWindowIfFullScreen()

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
        screen.duringOperation("moveFocusedWindow(\(workspace))") {
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

        if let workspace = workspaces.workspace(for: win.id) {
            workspaces.saveFocusedWindowInWorkspace(workspace, win.id)
        } else {
            assignWindowToWorkspace(win, workspaces.currentWorkspace)
        }
    }

    private func handleDestroyed(_ windowId: CGWindowID) {
        let hasTabSiblings = !workspaces.tabSiblings(of: windowId).isEmpty
        unmanage(windowId, "destroyed")

        if !hasTabSiblings {
            restoreWindowsFocusForWorkspace()
        }
    }

    private func handleMinimized(_ windowId: CGWindowID) {
        guard workspaces.workspace(for: windowId) != nil else { return }

        unmanage(windowId, "minimized")

        restoreWindowsFocusForWorkspace()
    }

    private func dropFocusedWindowIfFullScreen() {
        guard let focused = screen.focused(), focused.isFullScreen,
              workspaces.workspace(for: focused.id) != nil
        else { return }

        unmanage(focused.id, "fullscreen")
    }

    // A window out of reach cannot be parked, and focusing it would strand the user
    // away from the desktop: a minimized one is off screen, a full screen one owns its
    // own native space, a destroyed one is gone for good. It stops being managed
    // rather than being flagged, and a window that comes back joins whatever workspace
    // is current, like a brand new one.
    private func unmanage(_ windowId: CGWindowID, _ reason: String) {
        let workspace = workspaces.workspace(for: windowId).map { String($0) } ?? "none"
        Log.engine.info("\(reason) id=\(windowId), dropped from workspace \(workspace)")

        workspaces.unregisterWindowById(windowId)
        desktop.forget(windowId)
    }

    // Focusing a hidden window means the user navigated to it behind OttoWM's back
    // (Cmd-Tab/Dock on the same native Space, or Mission Control from another one),
    // so follow them by switching to that window's workspace.
    private func handleManualNavigation(_ windowId: CGWindowID) {
        screen.duringOperation("handleManualNavigation") {
            if ignoreNextManualNavigation {
                ignoreNextManualNavigation = false
                Log.engine.debug("ignoring manual navigation (one-shot)")
                return
            }

            if currentWorkspaceIsClosing() { return }

            let target = workspaces.workspace(for: windowId) ?? 1
            Log.engine.info("manual navigation → workspace \(target) window id=\(windowId)")
            transitionToWorkspace(target)
        }
    }

    private func transitionToWorkspace(_ workspace: Int) {
        let focusToKeep = screen.focused().flatMap { isValidWindow($0) ? $0.id : nil }

        let placements = workspaces.switchTo(workspace, leavingFocusOn: focusToKeep)
        Log.engine.info("switching to \(workspace) toActive=\(placements.toActive) toStorage=\(placements.toStorage)")
        for windowId in placements.toActive {
            desktop.place(windowId, .active)
        }
        for windowId in placements.toStorage {
            desktop.place(windowId, .storage)
        }
    }

    private func assignWindowToWorkspace(_ win: WindowSnapshot, _ workspace: Int) {
        guard isValidWindow(win) else { return }
        workspaces.assignWindowToWorkspace(win, workspace)
        Log.engine.info("assigned \(win.logDescription) → workspace \(workspace)")
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
        screen.duringOperation("restoreWindowsFocus") {
            let currentWorkspace = workspaces.currentWorkspace

            if let osFocused = screen.focused(), isValidWindow(osFocused) {
                let workspace = workspaces.workspace(for: osFocused.id)
                if workspace == currentWorkspace {
                    workspaces.saveFocusedWindowInWorkspace(currentWorkspace, osFocused.id)
                    return true
                }
                // A window that left management while it was out of reach is back. It joins the
                // workspace the user is on now, like a newly created one.
                if workspace == nil {
                    assignWindowToWorkspace(osFocused, currentWorkspace)
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

    // The single admission gate: anything entering the model passes through here.
    private func isValidWindow(_ win: WindowSnapshot) -> Bool {
        win.id != 0 && win.isStandard && !win.isFullScreen && !win.isMinimized
            && screen.shows(win.id)
    }

    // AX still resolves elements of windows that are already gone, so a workspace whose
    // windows are all mid-destruction still answers focus events. Neither on screen nor
    // merely minimized means the window is on its way out.
    private func currentWorkspaceIsClosing() -> Bool {
        let windowIds = workspaces.windowIds(in: workspaces.currentWorkspace)

        return !windowIds.isEmpty && windowIds.allSatisfy { windowId in
            guard let win = screen.snapshot(of: windowId) else { return true }
            return !screen.shows(windowId) && !win.isMinimized
        }
    }
}
