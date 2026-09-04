import CoreGraphics

/// Keeps the focus and the current workspace together. `restore` makes the focus agree with
/// the current workspace after a change; `follow` and `navigate` make the workspace agree
/// with the window the user focused.
final class Navigation {
    private let desktop: any Desktop
    private let windowSystem: WindowSystem
    private let workspaces: Workspaces
    private let managed: ManagedWindows
    private let enrollment: WindowEnrollment
    private var expectedNavigation = false

    init(
        desktop: any Desktop,
        windowSystem: WindowSystem,
        workspaces: Workspaces,
        managed: ManagedWindows,
        enrollment: WindowEnrollment
    ) {
        self.desktop = desktop
        self.windowSystem = windowSystem
        self.workspaces = workspaces
        self.managed = managed
        self.enrollment = enrollment
    }

    /// The focused event: manual navigation to a parked window, a stale event, a window not
    /// yet on screen, a window back from full screen, a tab of a group parked elsewhere.
    func follow(_ win: WindowSnapshot) {
        if managed.placement(of: win.id) == .parked {
            guard windowSystem.focused()?.id == win.id else {
                Log.engine.debug("ignoring stale focus event id=\(win.id)")
                return
            }
            navigate(to: win.id)
            return
        }

        guard managed.canManage(win) else {
            enrollment.enrollLater(win)
            return
        }

        switch workspaces.membership(of: win, whenNew: workspaces.current) {
        case let .fullScreen(workspace):
            guard !managed.followBackFromFullScreen(win, to: workspace) else { return }
            enroll(win, into: workspaces.current)
        case let .assigned(workspace):
            workspaces.recordFocus(on: win.id, in: workspace)
        case let .unassigned(workspace):
            enroll(win, into: workspace)
        }
    }

    func navigate(to windowId: CGWindowID) {
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
                focusSettled = managed.unmanage(closedId, reason: "closed") || focusSettled
            }

            if !focusSettled {
                restore()
            }
            return
        }

        let target = workspaces.workspace(for: windowId) ?? 1
        Log.engine.info("manual navigation → workspace \(target) window id=\(windowId)")
        managed.switchTo(target)
    }

    @discardableResult
    func restore() -> Bool {
        let currentWorkspace = workspaces.current

        if let osFocused = windowSystem.focused(), managed.canManage(osFocused) {
            switch workspaces.membership(of: osFocused, whenNew: currentWorkspace) {
            case let .fullScreen(workspace):
                if managed.followBackFromFullScreen(osFocused, to: workspace) { return true }
            case let .assigned(workspace) where workspace == currentWorkspace:
                workspaces.recordFocus(on: osFocused.id, in: currentWorkspace)
                return true
            case .unassigned:
                if managed.assign(osFocused, to: currentWorkspace) == currentWorkspace { return true }
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

    func returnToDesktop() {
        guard !restore() else { return }

        expectedNavigation = true
        Log.engine.debug("returning to desktop, ignoring next manual navigation")

        if let windowId = workspaces.allWindowIds.first(where: { desktop.focus($0) }) {
            Log.engine.debug("brought the desktop to front via id=\(windowId)")
            return
        }
        Log.engine.debug("no live managed window to bring the desktop to front")
    }

    /// The focused window when the current workspace holds it, enrolled first when no
    /// workspace does. See `WindowEnrollment` for how a live window ends up in no workspace.
    func focusedWindowOfCurrentWorkspace() -> WindowSnapshot? {
        guard let focused = windowSystem.focused() else { return nil }

        switch workspaces.workspace(for: focused.id) {
        case workspaces.current: return focused
        case nil: return managed.assign(focused, to: workspaces.current) == workspaces.current ? focused : nil
        default: return nil
        }
    }

    private func enroll(_ win: WindowSnapshot, into workspace: Int) {
        guard let assigned = managed.assign(win, to: workspace), assigned != workspaces.current else { return }
        navigate(to: win.id)
    }
}
