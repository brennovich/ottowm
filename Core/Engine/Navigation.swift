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

        switch workspaces.membership(of: win.id) {
        case let .fullScreen(workspace):
            guard !placement.followBackFromFullScreen(win, to: workspace) else { return }
            enroll(win)
        case let .assigned(workspace):
            workspaces.recordFocus(on: win.id, in: workspace)
        case .unassigned:
            enroll(win)
        }
    }

    func navigate(to windowId: CGWindowID) {
        let closed = placement.closedWindows()
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
            switch workspaces.membership(of: osFocused.id) {
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

        Log.engine.debug("returning to desktop through the anchor")
        desktop.anchor.focus()
    }

    /// The focused window when the current workspace holds it, enrolled first when no
    /// workspace does. See `WindowEnrollment` for how a live window ends up in no workspace.
    func focusedWindowOfCurrentWorkspace() -> WindowSnapshot? {
        guard let focused = windowSystem.focused() else { return nil }
        guard placement.assign(focused, to: workspaces.current).workspace == workspaces.current else { return nil }

        workspaces.regroupTabs(of: focused)
        return focused
    }

    private func enroll(_ win: WindowSnapshot) {
        guard let assigned = enrollment.enroll(win, to: workspaces.current), assigned != workspaces.current else { return }
        navigate(to: win.id)
    }
}
