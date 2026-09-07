import CoreGraphics

/// Keeps a window's workspace membership and its placement on the desktop in step: a window
/// of the current workspace is active, any other is parked.
final class WindowPlacement {
    private let desktop: any Desktop
    private let windowSystem: WindowSystem
    private let workspaces: Workspaces
    private let admission: Admission
    private let parkedWindows: ParkedWindows
    private let filledWindows: FilledWindows

    init(
        desktop: any Desktop,
        windowSystem: WindowSystem,
        workspaces: Workspaces,
        admission: Admission,
        parkedWindows: ParkedWindows,
        filledWindows: FilledWindows
    ) {
        self.desktop = desktop
        self.windowSystem = windowSystem
        self.workspaces = workspaces
        self.admission = admission
        self.parkedWindows = parkedWindows
        self.filledWindows = filledWindows
    }

    func isParked(_ windowId: CGWindowID) -> Bool {
        parkedWindows.isParked(windowId)
    }

    var parked: [(windowId: CGWindowID, parkedFrom: CGRect)] {
        parkedWindows.all
    }

    @discardableResult
    func assign(_ win: WindowSnapshot, to workspace: Int) -> Int? {
        if let known = workspaces.workspace(for: win.id) { return known }
        guard admission.verdict(for: win) == .admit else { return nil }

        let assigned = workspaces.assign(win, to: workspace)
        filledWindows.shareFrame(with: win.id)
        Log.engine.info("assigned \(win.logDescription) → workspace \(assigned)")

        place(win.id, parked: assigned != workspaces.current)
        return assigned
    }

    /// - Returns: `true` when the focus is settled without OttoWM: a tab sibling kept it, or
    ///   the window was never managed. macOS moves the focus off a window it destroys, and
    ///   choosing where it goes next is OttoWM's call only for a window it managed: doing it
    ///   for a dialog, or a window of another native Space, pulls the focus into the current
    ///   workspace.
    @discardableResult
    func drop(_ windowId: CGWindowID, reason: String) -> Bool {
        let workspace = workspaces.workspace(for: windowId)
        let from = workspace.map { String($0) } ?? "none"
        Log.engine.info("\(reason) id=\(windowId), dropped from workspace \(from)")

        // Forgetting a parked window leaves it at the hidden edge with nothing left to
        // bring it back.
        if parkedWindows.isParked(windowId) {
            place(windowId, parked: false)
        }

        let focusSettled = workspaces.remove(windowId)
        parkedWindows.forget(windowId)
        filledWindows.forget(windowId)
        return focusSettled || workspace == nil
    }

    @discardableResult
    func move(_ win: WindowSnapshot, to workspace: Int) -> Bool {
        guard admission.verdict(for: win) == .admit else { return false }

        let parked = workspace != workspaces.current
        Log.engine.info("moving window \(win.logDescription) to workspace \(workspace) parked=\(parked)")
        place(win.id, parked: parked)
        workspaces.move(win.id, to: workspace)
        return true
    }

    /// The record is taken after the removal, which clears every other trace of the window.
    func releaseToFullScreen(_ windowId: CGWindowID, from workspace: Int) {
        drop(windowId, reason: "fullscreen")
        workspaces.recordFullScreen(windowId, leaving: workspace)
    }

    func followBackFromFullScreen(_ win: WindowSnapshot, to workspace: Int) -> Bool {
        guard admission.verdict(for: win) == .admit else { return false }

        Log.engine.info("\(win.logDescription) is back from full screen → workspace \(workspace)")
        if workspace != workspaces.current {
            switchTo(workspace)
        }
        return assign(win, to: workspace) != nil
    }

    func switchTo(_ workspace: Int) {
        let focusToKeep = windowSystem.focused().flatMap { admission.verdict(for: $0) == .admit ? $0.id : nil }
        let placements = workspaces.switchTo(workspace, leavingFocusOn: focusToKeep)
        Log.engine.info("switching to \(workspace) activating=\(placements.activating) parking=\(placements.parking)")

        let batch = placements.activating.map { (windowId: $0, parked: false) }
            + placements.parking.map { (windowId: $0, parked: true) }
        place(batch).forEach { drop($0, reason: "gone") }
    }

    /// A parked window on screen proves the native Space in front is OttoWM's own, so the
    /// active windows the screen no longer shows are the ones that left it. A tab hidden by
    /// its sibling and a window gone full screen are still there.
    func dropWindowsThatLeftTheDesktop() {
        let parked = workspaces.allWindowIds.filter { parkedWindows.isParked($0) }
        guard windowSystem.showsAny(parked) else { return }

        for windowId in workspaces.allWindowIds.subtracting(parked)
        where !windowSystem.showsAny(Set(workspaces.tabGroupMembers(of: windowId))) {
            guard let snapshot = windowSystem.snapshot(of: windowId), !snapshot.isFullScreen else { continue }
            drop(windowId, reason: "left the desktop")
        }
    }

    func restoreParkedWindows() {
        let restoring = parkedWindows.all.map { (windowId: $0.windowId, parked: false) }
        Log.engine.info("restoring \(restoring.count) parked windows")
        place(restoring)
    }

    /// Nothing to do for a window already parked: parking it again would record the hidden
    /// edge as the frame it was parked from.
    private func change(
        for request: (windowId: CGWindowID, parked: Bool)
    ) -> (windowId: CGWindowID, change: FrameChange)? {
        let parkedFrom = parkedWindows.parkedFrom(of: request.windowId)
        guard request.parked else { return (windowId: request.windowId, change: .unpark(parkedFrom)) }
        return parkedFrom == nil ? (windowId: request.windowId, change: .park) : nil
    }

    private func place(_ windowId: CGWindowID, parked: Bool) {
        place([(windowId: windowId, parked: parked)])
    }

    @discardableResult
    private func place(_ requests: [(windowId: CGWindowID, parked: Bool)]) -> [CGWindowID] {
        let outcomes = desktop.reframe(requests.compactMap(change(for:)))
        parkedWindows.record(outcomes)

        return outcomes.compactMap { outcome -> CGWindowID? in
            guard case let .gone(windowId) = outcome else { return nil }
            return windowId
        }
    }
}
