import CoreGraphics

/// Keeps the focus and the current workspace together. `restore` makes the focus agree with
/// the current workspace after a change; `follow` and `navigate` make the workspace agree
/// with the window the user focused.
final class Navigation {
    private let desktop: any Desktop
    private let windowSystem: WindowSystem
    private let workspaces: Workspaces
    private let placement: WindowPlacement
    private let enrollment: WindowEnrollment
    private var expectedNavigation = false

    init(
        desktop: any Desktop,
        windowSystem: WindowSystem,
        workspaces: Workspaces,
        placement: WindowPlacement,
        enrollment: WindowEnrollment
    ) {
        self.desktop = desktop
        self.windowSystem = windowSystem
        self.workspaces = workspaces
        self.placement = placement
        self.enrollment = enrollment
    }

    /// What a focus event can mean: manual navigation to a parked window, a stale event, a
    /// window not yet on screen, a window back from full screen, a tab of a group parked
    /// elsewhere.
    func follow(_ win: WindowSnapshot) {
        if placement.isParked(win.id) {
            guard windowSystem.focused()?.id == win.id else {
                Log.engine.debug("ignoring stale focus event id=\(win.id)")
                return
            }
            navigate(to: win.id)
            return
        }

        switch workspaces.membership(of: win, whenNew: workspaces.current) {
        case let .fullScreen(workspace):
            guard !placement.followBackFromFullScreen(win, to: workspace) else { return }
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
                focusSettled = placement.drop(closedId, reason: "closed") || focusSettled
            }

            if !focusSettled {
                restore()
            }
            return
        }

        let target = workspaces.workspace(for: windowId) ?? 1
        Log.engine.info("manual navigation → workspace \(target) window id=\(windowId)")
        placement.switchTo(target)
    }

    @discardableResult
    func restore() -> Bool {
        let currentWorkspace = workspaces.current

        if let osFocused = windowSystem.focused() {
            switch workspaces.membership(of: osFocused, whenNew: currentWorkspace) {
            case let .fullScreen(workspace):
                if placement.followBackFromFullScreen(osFocused, to: workspace) { return true }
            case let .assigned(workspace) where workspace == currentWorkspace:
                workspaces.recordFocus(on: osFocused.id, in: currentWorkspace)
                return true
            case .unassigned:
                if placement.assign(osFocused, to: currentWorkspace).workspace == currentWorkspace { return true }
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
        guard placement.assign(focused, to: workspaces.current).workspace == workspaces.current else { return nil }

        workspaces.regroupTabs(of: focused)
        return focused
    }

    private func enroll(_ win: WindowSnapshot, into workspace: Int) {
        guard let assigned = enrollment.enroll(win, to: workspace), assigned != workspaces.current else { return }
        navigate(to: win.id)
    }
}
