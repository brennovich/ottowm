import CoreGraphics

/// The windows that belong to a workspace. Keeps each one's membership and its placement on
/// the desktop in step: a window of the current workspace is active, any other is parked.
final class ManagedWindows {
    private let desktop: any Desktop
    private let windowSystem: WindowSystem
    private let workspaces: Workspaces
    private let parkedWindows: ParkedWindows

    init(desktop: any Desktop, windowSystem: WindowSystem, workspaces: Workspaces, parkedWindows: ParkedWindows) {
        self.desktop = desktop
        self.windowSystem = windowSystem
        self.workspaces = workspaces
        self.parkedWindows = parkedWindows
    }

    var isDesktopInFront: Bool {
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

    func placement(of windowId: CGWindowID) -> Placement {
        parkedWindows.placement(of: windowId)
    }

    var parked: [(windowId: CGWindowID, owedFrame: CGRect)] {
        parkedWindows.all
    }

    @discardableResult
    func assign(_ win: WindowSnapshot, to workspace: Int) -> Int? {
        guard canManage(win) else { return nil }

        let assigned = workspaces.assign(win, to: workspace)
        Log.engine.info("assigned \(win.logDescription) → workspace \(assigned)")

        place(win.id, at: assigned == workspaces.current ? .active : .parked)
        return assigned
    }

    /// - Returns: `true` when the focus is settled without OttoWM: a tab sibling kept it, or
    ///   the window was never managed. macOS moves the focus off a window it destroys, and
    ///   choosing where it goes next is OttoWM's call only for a window it managed: doing it
    ///   for a dialog, or a window of another native Space, pulls the focus into the current
    ///   workspace.
    @discardableResult
    func unmanage(_ windowId: CGWindowID, reason: String) -> Bool {
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

    @discardableResult
    func move(_ win: WindowSnapshot, to workspace: Int) -> Bool {
        guard canManage(win) else { return false }

        let placement: Placement = workspace == workspaces.current ? .active : .parked
        Log.engine.info("moving window \(win.logDescription) to workspace \(workspace) placement=\(placement)")
        place(win.id, at: placement)
        workspaces.move(win.id, to: workspace)
        return true
    }

    /// The record is taken after the removal, which clears every other trace of the window.
    func releaseToFullScreen(_ windowId: CGWindowID, from workspace: Int) {
        unmanage(windowId, reason: "fullscreen")
        workspaces.recordFullScreen(windowId, leaving: workspace)
    }

    func followBackFromFullScreen(_ win: WindowSnapshot, to workspace: Int) -> Bool {
        guard canManage(win) else { return false }

        Log.engine.info("\(win.logDescription) is back from full screen → workspace \(workspace)")
        if workspace != workspaces.current {
            switchTo(workspace)
        }
        return assign(win, to: workspace) != nil
    }

    func switchTo(_ workspace: Int) {
        let focusToKeep = windowSystem.focused().flatMap { canManage($0) ? $0.id : nil }
        let placements = workspaces.switchTo(workspace, leavingFocusOn: focusToKeep)
        Log.engine.info("switching to \(workspace) activating=\(placements.activating) parking=\(placements.parking)")

        let batch = placements.activating.map { (windowId: $0, placement: Placement.active) }
            + placements.parking.map { (windowId: $0, placement: Placement.parked) }
        place(batch).forEach { unmanage($0, reason: "gone") }
    }

    /// A parked window on screen proves the native Space in front is OttoWM's own, so the
    /// active windows the screen no longer shows are the ones that left it. A tab hidden by
    /// its sibling and a window gone full screen are still there.
    func dropWindowsThatLeftTheDesktop() {
        let parked = workspaces.allWindowIds.filter { parkedWindows.placement(of: $0) == .parked }
        guard windowSystem.showsAny(parked) else { return }

        for windowId in workspaces.allWindowIds.subtracting(parked)
        where !windowSystem.showsAny(Set(workspaces.tabGroupMembers(of: windowId))) {
            guard let snapshot = windowSystem.snapshot(of: windowId), !snapshot.isFullScreen else { continue }
            unmanage(windowId, reason: "left the desktop")
        }
    }

    func restoreParkedWindows() {
        let parked = parkedWindows.all.map { (windowId: $0.windowId, placement: Placement.active) }
        Log.engine.info("restoring \(parked.count) parked windows")
        place(parked)
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
}
