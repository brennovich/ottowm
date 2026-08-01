import CoreGraphics

// Orchestrates windows lifecycle events and hotkey commands, keeping the pure
// Workspaces model and the physical Desktop in sync.
final class Engine {
    private let desktop: any Desktop
    private let window: (CGWindowID) -> (any Window)?
    private let focusedWindow: OperationCache<WindowSnapshot?>
    private let onScreenWindows: OperationCache<Set<CGWindowID>>
    private let model = Workspaces()
    private var ignoreNextManualNavigation = false

    init(
        desktop: any Desktop,
        window: @escaping (CGWindowID) -> (any Window)?,
        focusedWindow: OperationCache<WindowSnapshot?>,
        onScreenWindows: OperationCache<Set<CGWindowID>>
    ) {
        self.desktop = desktop
        self.window = window
        self.focusedWindow = focusedWindow
        self.onScreenWindows = onScreenWindows
    }

    var currentWorkspace: Int {
        model.currentWorkspace
    }

    var managedWindowIds: Set<CGWindowID> {
        model.allWindowIds
    }

    func start(windows: [WindowSnapshot]) {
        operation("start") {
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
        duringOperation {
            switch event {
            case let .created(win):
                assignWindowToWorkspace(win, model.currentWorkspace)
            case let .focused(win):
                handleFocused(win)
            case let .destroyed(windowId):
                handleDestroyed(windowId)
            case let .minimized(windowId):
                handleMinimized(windowId)
            case let .unminimized(win):
                assignWindowToWorkspace(win, model.currentWorkspace)
            }
        }
    }

    func switchToWorkspace(_ workspace: Int) {
        operation("switchToWorkspace(\(workspace))") {
            dropFocusedWindowIfFullScreen()

            let onDesktop = anyManagedWindowIsOnScreen || model.allWindowIds.isEmpty
            Log.engine.info("switch requested target=\(workspace) current=\(self.model.currentWorkspace) onDesktop=\(onDesktop)")

            if workspace == model.currentWorkspace {
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
        operation("moveFocusedWindow(\(workspace))") {
            guard workspace >= 1 else {
                Log.engine.info("move dropped: invalid workspace \(workspace)")
                return
            }
            guard let win = focusedWindow.value(), isValidWindow(win) else {
                Log.engine.info("move to \(workspace) dropped: no valid window to move")
                return
            }

            let placement: Placement = workspace == model.currentWorkspace ? .active : .storage
            Log.engine.info("moving window \(win.logDescription) to workspace \(workspace) placement=\(placement)")
            desktop.place(win.id, placement)
            model.moveWindowToWorkspace(win.id, workspace)

            restoreWindowsFocusForWorkspace()
        }
    }

    private func handleFocused(_ win: WindowSnapshot) {
        if desktop.placement(of: win.id) == .storage {
            // Focus notifications are delivered asynchronously, so this one may
            // describe a focus OttoWM itself caused before the switch that hid the
            // window. Acting on such an echo bounces straight back to the workspace we
            // just left. Only the window the OS considers focused right now counts.
            guard focusedWindow.value()?.id == win.id else {
                Log.engine.debug("ignoring stale focus event id=\(win.id)")
                return
            }
            handleManualNavigation(win.id)
            return
        }

        guard isValidWindow(win) else { return }

        if let workspace = model.workspace(for: win.id) {
            model.saveFocusedWindowInWorkspace(workspace, win.id)
        } else {
            assignWindowToWorkspace(win, model.currentWorkspace)
        }
    }

    private func handleDestroyed(_ windowId: CGWindowID) {
        let hasTabSiblings = model.tabSiblings(of: windowId) != nil
        Log.engine.debug("destroyed id=\(windowId) hadTabSiblings=\(hasTabSiblings)")
        unmanage(windowId)

        if !hasTabSiblings {
            restoreWindowsFocusForWorkspace()
        }
    }

    // A minimized window is out of reach: it cannot be moved, and focusing it would
    // bring it back on screen. It stops being managed until the user restores it,
    // and then joins whatever workspace is current.
    private func handleMinimized(_ windowId: CGWindowID) {
        guard let workspace = model.workspace(for: windowId) else { return }
        Log.engine.info("minimized id=\(windowId), dropped from workspace \(workspace)")

        unmanage(windowId)

        restoreWindowsFocusForWorkspace()
    }

    // A window taken full screen gets its own native space, where it is the only
    // thing on screen: it cannot be parked, and focusing it would keep the user
    // there instead of bringing the desktop back. Like a minimized one, it stops
    // being managed until it comes back.
    private func dropFocusedWindowIfFullScreen() {
        guard let focused = focusedWindow.value(), focused.isFullScreen,
              let workspace = model.workspace(for: focused.id)
        else { return }

        Log.engine.info("full screen id=\(focused.id), dropped from workspace \(workspace)")
        unmanage(focused.id)
    }

    private func unmanage(_ windowId: CGWindowID) {
        model.unregisterWindowById(windowId)
        desktop.forget(windowId)
    }

    // The desktop is in front when at least one window we manage is on screen:
    // a native Space showing something else (a full screen app) shows none of them.
    private var anyManagedWindowIsOnScreen: Bool {
        !onScreenWindows.value().isDisjoint(with: model.allWindowIds)
    }

    // Focusing any managed window pulls the native Space they all live on back to
    // the front, which is the only way back when the current workspace is empty.
    private func focusAnyManagedWindow() {
        for windowId in model.allWindowIds {
            if let win = window(windowId) {
                Log.engine.debug("bringing desktop to front via id=\(windowId)")
                win.focus()
                return
            }
        }
        Log.engine.debug("no live managed window to bring the desktop to front")
    }

    // Focusing a hidden window means the user navigated to it behind OttoWM's back
    // (Cmd-Tab/Dock on the same native Space, or Mission Control from another one),
    // so follow them by switching to that window's workspace.
    private func handleManualNavigation(_ windowId: CGWindowID) {
        operation("handleManualNavigation") {
            if ignoreNextManualNavigation {
                ignoreNextManualNavigation = false
                Log.engine.debug("ignoring manual navigation (one-shot)")
                return
            }

            if currentWorkspaceIsClosing() { return }

            let target = model.workspace(for: windowId) ?? 1
            Log.engine.info("manual navigation → workspace \(target) window id=\(windowId)")
            transitionToWorkspace(target)
        }
    }

    private func transitionToWorkspace(_ workspace: Int) {
        let focusToKeep = focusedWindow.value().flatMap { isValidWindow($0) ? $0.id : nil }

        let placements = model.switchTo(workspace, leavingFocusOn: focusToKeep)
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
        model.assignWindowToWorkspace(win, workspace)
        Log.engine.info("assigned \(win.logDescription) → workspace \(workspace)")
    }

    private func returnToDesktop() {
        if !restoreWindowsFocusForWorkspace() {
            ignoreNextManualNavigation = true
            Log.engine.debug("returning to desktop, ignoring next manual navigation")
            focusAnyManagedWindow()
        }
    }

    @discardableResult
    private func restoreWindowsFocusForWorkspace() -> Bool {
        operation("restoreWindowsFocus") {
            let currentWorkspace = model.currentWorkspace

            if let osFocused = focusedWindow.value(), isValidWindow(osFocused) {
                let workspace = model.workspace(for: osFocused.id)
                if workspace == currentWorkspace {
                    model.saveFocusedWindowInWorkspace(currentWorkspace, osFocused.id)
                    return true
                }
                // On screen, focused, and in no workspace: a window that left
                // management while it was out of reach is back. It joins the workspace
                // the user is on now, like a newly created one.
                if workspace == nil {
                    assignWindowToWorkspace(osFocused, currentWorkspace)
                    return true
                }
            }

            if let windowId = model.nextWindowToFocus(),
               let win = window(windowId) {
                win.focus()
                return true
            }

            Log.engine.debug("no window to focus in workspace \(currentWorkspace)")
            return false
        }
    }

    // An operation is the unit telemetry and both IPC-backed reads are scoped to:
    // `isValidWindow` asks which windows are on screen several times per operation and
    // the focused window is read more than once, and each ask would otherwise be its
    // own round trip.
    private func operation<T>(_ name: String, _ body: () -> T) -> T {
        duringOperation { Telemetry.shared.span(name, body) }
    }

    private func duringOperation<T>(_ body: () -> T) -> T {
        onScreenWindows.duringOperation { focusedWindow.duringOperation(body) }
    }

    private func isValidWindow(_ win: WindowSnapshot) -> Bool {
        win.id != 0 && win.isStandard && !win.isFullScreen && !win.isMinimized && isOnScreen(win.id)
    }

    private func isOnScreen(_ windowId: CGWindowID) -> Bool {
        onScreenWindows.value().contains(windowId)
    }

    // True while the current workspace's windows are all mid-destruction: the
    // model still lists them but none of them is on screen anymore. Focus events
    // fired during that teardown must not be mistaken for manual navigation.
    private func currentWorkspaceIsClosing() -> Bool {
        let windowIds = model.windowIds(in: model.currentWorkspace)
        if windowIds.isEmpty { return false }

        return windowIds.allSatisfy(windowIsGone)
    }

    // A closed window outlives its destruction notification: its AX element keeps
    // resolving until the notification arrives, so presence on screen is what says
    // it is gone. A minimized window is off screen too, and AX still answers for it.
    private func windowIsGone(_ windowId: CGWindowID) -> Bool {
        guard let win = window(windowId) else { return true }
        return !isOnScreen(windowId) && !win.snapshot().isMinimized
    }
}
