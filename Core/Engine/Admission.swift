import CoreGraphics

/// Whether OttoWM can take a window into a workspace.
///
/// The shape of a window does not change, so a window it rules out is refused for good. The
/// native Space in front and the on-screen list do change, so a window they rule out is worth
/// reading again.
final class Admission {
    enum Verdict: Equatable {
        case admit
        case retry
        case refuse
    }

    private let windowSystem: WindowSystem
    private let workspaces: Workspaces

    init(windowSystem: WindowSystem, workspaces: Workspaces) {
        self.windowSystem = windowSystem
        self.workspaces = workspaces
    }

    var isDesktopInFront: Bool {
        let managed = workspaces.allWindowIds
        if managed.isEmpty || windowSystem.showsAny(managed) { return true }

        guard let focused = windowSystem.focused(), windowSystem.shows(focused.id) else { return false }
        return workspaces.hasTabGroup(for: focused)
    }

    func verdict(for win: WindowSnapshot) -> Verdict {
        guard win.isAdmissible else {
            Log.engine.debug("\(win.logDescription) not admitted: not admissible")
            return .refuse
        }
        guard isDesktopInFront else {
            Log.engine.debug("\(win.logDescription) not admitted: another native Space is in front")
            return .retry
        }
        guard windowSystem.shows(win.id) else {
            Log.engine.debug("\(win.logDescription) not admitted: not on screen")
            return .retry
        }

        return .admit
    }
}
