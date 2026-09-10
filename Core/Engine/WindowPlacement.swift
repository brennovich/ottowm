import CoreGraphics

/// Keeps a window's workspace membership and its placement on the desktop in step: a window
/// of the current workspace is active, any other is parked.
final class WindowPlacement {
    enum Placement: Equatable {
        case assigned(Int)
        case refused(Admission.Verdict)

        var workspace: Int? {
            if case let .assigned(workspace) = self { workspace } else { nil }
        }
    }

    private let desktop: any Desktop
    private let windowSystem: WindowSystem
    private let workspaces: Workspaces
    private let admission: Admission
    private let parkedWindows: ParkedWindows
    private let restoringFrames: RestoringFrames
    private let layouts: DisplayLayouts

    init(
        desktop: any Desktop,
        windowSystem: WindowSystem,
        workspaces: Workspaces,
        admission: Admission,
        parkedWindows: ParkedWindows,
        restoringFrames: RestoringFrames,
        layouts: DisplayLayouts
    ) {
        self.desktop = desktop
        self.windowSystem = windowSystem
        self.workspaces = workspaces
        self.admission = admission
        self.parkedWindows = parkedWindows
        self.restoringFrames = restoringFrames
        self.layouts = layouts
    }

    func isParked(_ windowId: CGWindowID) -> Bool {
        parkedWindows.isParked(windowId)
    }

    var parked: [(windowId: CGWindowID, parkedFrom: CGRect)] {
        parkedWindows.all
    }

    var isDesktopInFront: Bool {
        admission.isDesktopInFront
    }

    func remember(_ win: WindowSnapshot) {
        remember([win.id: win.frame])
    }

    /// A parked window stands at the hidden edge, which is no frame to go back to.
    func remember(_ frames: [CGWindowID: CGRect]) {
        for (windowId, frame) in frames where !parkedWindows.isParked(windowId) {
            layouts.record(frame, of: windowId)
        }
    }

    @discardableResult
    func assign(_ win: WindowSnapshot, to workspace: Int) -> Placement {
        remember(win)
        if let known = workspaces.workspace(for: win.id) { return .assigned(known) }

        let verdict = admission.verdict(for: win)
        guard verdict == .admit else { return .refused(verdict) }

        let assigned = workspaces.assign(win, to: workspace)
        restoringFrames.shareFrame(with: win.id)
        Log.engine.info("assigned \(win.logDescription) → workspace \(assigned)")

        place(win.id, parked: assigned != workspaces.current)
        return .assigned(assigned)
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
        restoringFrames.forget(windowId)
        layouts.forget(windowId)
        return focusSettled || workspace == nil
    }

    @discardableResult
    func move(_ win: WindowSnapshot, to workspace: Int) -> Bool {
        guard admission.verdict(for: win) == .admit else { return false }
        workspaces.regroupTabs(of: win)

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
        return assign(win, to: workspace).workspace != nil
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

        for windowId in workspaces.allWindowIds.subtracting(parked) where !showsAnyTab(of: windowId) {
            guard let snapshot = windowSystem.snapshot(of: windowId), !snapshot.isFullScreen else { continue }
            drop(windowId, reason: "left the desktop")
        }
    }

    /// The windows of the current workspace the screen no longer shows and that are neither
    /// minimized nor full screen. A tab hidden by its sibling is still there. A window
    /// without a snapshot has left the registry, so its `destroyed` event is on its way.
    func closedWindows() -> [CGWindowID] {
        workspaces.windowIds(in: workspaces.current).filter { windowId in
            guard let snapshot = windowSystem.snapshot(of: windowId) else { return false }
            return !showsAnyTab(of: windowId) && !snapshot.isMinimized && !snapshot.isFullScreen
        }
    }

    /// - Parameter change: takes the frame a maximize or a fill of the window goes back to.
    func reframe(_ win: WindowSnapshot, _ change: (_ restoring: CGRect?) -> FrameChange) {
        let requested = change(restoringFrames.restoringFrame(of: win.id))
        Log.engine.info("\(requested.logDescription) \(win.logDescription)")

        let outcomes = desktop.reframe([(windowId: win.id, change: requested)])
        restoringFrames.record(outcomes)
        if outcomes.contains(.gone(win.id)) {
            drop(win.id, reason: "gone")
        }
    }

    /// Puts every managed window where it last stood on the display entered, or at its last
    /// frame on the display left fitted into the new one. A parked window goes to the new
    /// hidden edge, and comes back to that frame.
    func relocate(from old: Display, to new: Display) {
        let fit = Fit(from: old.visibleFrame, into: new.visibleFrame)
        restoringFrames.relocate(with: fit)

        let changes = workspaces.allWindowIds.sorted().compactMap { windowId in
            change(relocating: windowId, from: old, to: new, with: fit)
        }
        Log.engine.info("display changed to \(new.logDescription), placing \(changes.count) windows")
        apply(changes).forEach { drop($0, reason: "gone") }
    }

    func restoreParkedWindows() {
        let restoring = parkedWindows.all.map { (windowId: $0.windowId, parked: false) }
        Log.engine.info("restoring \(restoring.count) parked windows")
        place(restoring)
    }

    /// On the same display only the parked windows move, to the edge of its new geometry: the
    /// frame remembered for an active window may be older than where the user left it.
    private func change(
        relocating windowId: CGWindowID, from old: Display, to new: Display, with fit: Fit
    ) -> (windowId: CGWindowID, change: FrameChange)? {
        let parkedFrom = parkedWindows.parkedFrom(of: windowId)
        guard old.id != new.id else {
            return parkedFrom.map { (windowId: windowId, change: .park(from: fit.frame($0))) }
        }
        guard let last = layouts.frame(of: windowId, on: old.id) ?? parkedFrom else { return nil }

        let target = layouts.frame(of: windowId, on: new.id) ?? fit.frame(last)
        layouts.record(target, of: windowId)
        return (windowId: windowId, change: parkedFrom == nil ? .unpark(target) : .park(from: target))
    }

    /// Nothing to do for a window already parked: parking it again would record the hidden
    /// edge as the frame it was parked from.
    private func change(
        for request: (windowId: CGWindowID, parked: Bool)
    ) -> (windowId: CGWindowID, change: FrameChange)? {
        let parkedFrom = parkedWindows.parkedFrom(of: request.windowId)
        guard request.parked else { return (windowId: request.windowId, change: .unpark(parkedFrom)) }
        return parkedFrom == nil ? (windowId: request.windowId, change: .park(from: nil)) : nil
    }

    private func showsAnyTab(of windowId: CGWindowID) -> Bool {
        windowSystem.showsAny(Set(workspaces.tabGroupMembers(of: windowId)))
    }

    private func place(_ windowId: CGWindowID, parked: Bool) {
        place([(windowId: windowId, parked: parked)])
    }

    @discardableResult
    private func place(_ requests: [(windowId: CGWindowID, parked: Bool)]) -> [CGWindowID] {
        apply(requests.compactMap(change(for:)))
    }

    private func apply(_ changes: [(windowId: CGWindowID, change: FrameChange)]) -> [CGWindowID] {
        let outcomes = desktop.reframe(changes)
        parkedWindows.record(outcomes)
        layouts.record(outcomes)

        return outcomes.compactMap { outcome -> CGWindowID? in
            guard case let .gone(windowId) = outcome else { return nil }
            return windowId
        }
    }
}
