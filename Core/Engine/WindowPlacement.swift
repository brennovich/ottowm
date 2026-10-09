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
    private let originalFrames: OriginalFrames
    private let layouts: DisplayLayouts
    private let log: LogChannel

    init(
        desktop: any Desktop,
        windowSystem: WindowSystem,
        workspaces: Workspaces,
        admission: Admission,
        parkedWindows: ParkedWindows,
        originalFrames: OriginalFrames,
        layouts: DisplayLayouts,
        log: LogChannel = Log.engine
    ) {
        self.desktop = desktop
        self.windowSystem = windowSystem
        self.workspaces = workspaces
        self.admission = admission
        self.parkedWindows = parkedWindows
        self.originalFrames = originalFrames
        self.layouts = layouts
        self.log = log
    }

    func isParked(_ windowId: CGWindowID) -> Bool {
        parkedWindows.isParked(windowId)
    }

    var parked: [CGWindowID: CGRect] {
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
            layouts.record(frame, of: windowId, on: desktop.display.id)
        }
    }

    @discardableResult
    func assign(_ win: WindowSnapshot, to workspace: Int) -> Placement {
        remember(win)
        if let known = workspaces.workspace(for: win.id) { return .assigned(known) }

        let verdict = admission.verdict(for: win)
        guard verdict == .admit else { return .refused(verdict) }

        let assigned = holdingFirstWindows { workspaces.assign(win, to: workspace) }
        originalFrames.shareFrame(with: win.id)
        log.info("assigned \(win.logDescription) → workspace \(assigned)")

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
        if let workspace {
            log.info("\(reason) id=\(windowId), dropped from workspace \(workspace)")
        }

        // Forgetting a parked window leaves it at the hidden edge with nothing left to
        // bring it back.
        if parkedWindows.isParked(windowId) {
            place(windowId, parked: false)
        }

        let focusSettled = workspaces.remove(windowId)
        parkedWindows.forget(windowId)
        originalFrames.forget(windowId)
        layouts.forget(windowId)
        return focusSettled || workspace == nil
    }

    /// Takes out an active window that moved to another display, with its tab group. Its
    /// layouts stay: they hold where it stood on each display, which a display change goes
    /// back to. The frame a maximize goes back to is a frame on this display.
    func release(_ windowId: CGWindowID) {
        for memberId in workspaces.tabGroupMembers(of: windowId) {
            if let workspace = workspaces.workspace(for: memberId) {
                log.info("moved to another display id=\(memberId), released from workspace \(workspace)")
            }
            workspaces.remove(memberId)
            originalFrames.forget(memberId)
        }
    }

    @discardableResult
    func move(_ win: WindowSnapshot, to workspace: Int) -> Bool {
        guard admission.verdict(for: win) == .admit else { return false }
        workspaces.regroupTabs(of: win)

        let parked = workspace != workspaces.current
        log.info("moving window \(win.logDescription) to workspace \(workspace) parked=\(parked)")
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

        log.info("\(win.logDescription) is back from full screen → workspace \(workspace)")
        if workspace != workspaces.current {
            switchTo(workspace)
        }
        return assign(win, to: workspace).workspace != nil
    }

    func switchTo(_ workspace: Int) {
        let focusToKeep = windowSystem.focused().flatMap { admission.verdict(for: $0) == .admit ? $0.id : nil }
        let placements = workspaces.switchTo(workspace, leavingFocusOn: focusToKeep)
        log.info("switching to \(workspace) activating=\(placements.activating) parking=\(placements.parking)")

        let batch = placements.activating.map { (windowId: $0, parked: false) }
            + placements.parking.map { (windowId: $0, parked: true) }
        place(batch).gone.forEach { drop($0, reason: "gone") }
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
            guard !showsAnyTab(of: windowId), let snapshot = windowSystem.snapshot(of: windowId) else { return false }
            return !snapshot.isMinimized && !snapshot.isFullScreen
        }
    }

    /// - Parameter change: takes the frame a maximize or a tile of the window goes back to.
    func reframe(_ win: WindowSnapshot, _ change: (_ restoring: CGRect?) -> FrameChange) {
        let requested = change(originalFrames.originalFrame(of: win.id))
        log.info("\(requested.logDescription) \(win.logDescription)")

        let outcomes = apply([FrameRequest(windowId: win.id, change: requested)])
        // Recorded here and not in `apply`: an unpark reports `.active` too, which would drop
        // the frame a maximized window goes back to on every workspace switch.
        originalFrames.record(outcomes)
        outcomes.gone.forEach { drop($0, reason: "gone") }
    }

    /// Puts every managed window where it last stood on the display entered, or at its last
    /// frame on the display left fitted into the new one. A parked window goes to the new
    /// hidden edge, and comes back to that frame.
    func relocate(_ change: DisplayChange) {
        originalFrames.relocate(with: change.fit)
        relocate(workspaces.allWindowIds, in: change)
    }

    /// Takes the windows of a removed display into the workspaces of the same number and
    /// relocates them from that display. Relocating keeps a window parked or active as it was,
    /// so a window whose workspace is now current, or no longer current, is placed again.
    /// A window dragged across displays can be held by both engines until a reconcile; it
    /// keeps its place in this one.
    func absorb(_ removed: SavedState) {
        let absorbed = removed.workspaces.allWindowIds.subtracting(workspaces.allWindowIds)
        let saved = removed.keeping(absorbed)
        let change = DisplayChange(from: saved.display, to: desktop.display)
        holdingFirstWindows { workspaces.absorb(saved.workspaces) }
        parkedWindows.park(saved.parkedWindows)
        originalFrames.absorb(saved.originalFrames.mapValues(change.fit.frame))

        relocate(absorbed, in: change)

        let misplaced = absorbed.sorted().map { (windowId: $0, parked: workspaces.workspace(for: $0) != workspaces.current) }
            .filter { $0.parked != parkedWindows.isParked($0.windowId) }
        place(misplaced)
    }

    /// Puts the windows back in the workspaces the state holds them in, and takes the others
    /// into the current workspace. Every window of another workspace goes to the hidden edge,
    /// one the state holds as parked from its saved frame: a crash may have left it on
    /// screen. Any other window found at the hidden edge is brought back on screen.
    func restore(_ windows: [WindowSnapshot], from saved: SavedState?) {
        if let saved {
            holdingFirstWindows { load(saved.keeping(Set(windows.filter { admission.verdict(for: $0) == .admit }.map(\.id)))) }
            if saved.display != desktop.display {
                relocate(DisplayChange(from: saved.display, to: desktop.display))
            }

            let parking = workspaces.allWindowIds.subtracting(workspaces.windowIds(in: workspaces.current))
            let requests = parking.sorted().map { FrameRequest(windowId: $0, change: .park(from: parkedWindows.parkedFrom(of: $0))) }
            apply(requests).gone.forEach { drop($0, reason: "gone") }
        }

        for win in desktop.recover(windows.filter { !parkedWindows.isParked($0.id) }) {
            assign(win, to: workspaces.current)
        }
    }

    var savedState: SavedState {
        SavedState(
            display: desktop.display,
            workspaces: workspaces.record,
            parkedWindows: parkedWindows.all,
            originalFrames: originalFrames.all
        )
    }

    func restoreParkedWindows() {
        let restoring = parkedWindows.all.keys.sorted().map { (windowId: $0, parked: false) }
        log.info("restoring \(restoring.count) parked windows")
        place(restoring)
    }

    /// Pins the anchor when `body` takes the engine from holding no window to holding some.
    @discardableResult
    private func holdingFirstWindows<Result>(_ body: () -> Result) -> Result {
        let heldNone = workspaces.allWindowIds.isEmpty
        let result = body()
        if heldNone, !workspaces.allWindowIds.isEmpty { desktop.pinAnchor() }
        return result
    }

    private func load(_ saved: SavedState) {
        workspaces.load(saved.workspaces)
        parkedWindows.park(saved.parkedWindows)
        originalFrames.load(saved.originalFrames)
        log.notice("restored \(workspaces.allWindowIds.count) windows, workspace \(workspaces.current)")
    }

    private func relocate(_ windowIds: Set<CGWindowID>, in change: DisplayChange) {
        let requests = windowIds.sorted().compactMap { request(relocating: $0, in: change) }
        log.info("display changed to \(change.to.logDescription), placing \(requests.count) windows")
        apply(requests).gone.forEach { drop($0, reason: "gone") }
    }

    /// On the same display only the parked windows move, to the edge of its new geometry: the
    /// frame remembered for an active window may be older than where the user left it.
    private func request(relocating windowId: CGWindowID, in change: DisplayChange) -> FrameRequest? {
        let fit = change.fit
        let parkedFrom = parkedWindows.parkedFrom(of: windowId)
        guard !change.keepsDisplay else {
            return parkedFrom.map { FrameRequest(windowId: windowId, change: .park(from: fit.frame($0))) }
        }
        guard let last = layouts.frame(of: windowId, on: change.from.id) ?? parkedFrom else { return nil }

        let target = layouts.frame(of: windowId, on: change.to.id) ?? fit.frame(last)
        layouts.record(target, of: windowId, on: change.to.id)
        return FrameRequest(windowId: windowId, change: parkedFrom == nil ? .unpark(target) : .park(from: target))
    }

    /// Nothing to do for a window already parked: parking it again would record the hidden
    /// edge as the frame it was parked from.
    private func request(for placement: (windowId: CGWindowID, parked: Bool)) -> FrameRequest? {
        let parkedFrom = parkedWindows.parkedFrom(of: placement.windowId)
        guard placement.parked else { return FrameRequest(windowId: placement.windowId, change: .unpark(parkedFrom)) }
        return parkedFrom == nil ? FrameRequest(windowId: placement.windowId, change: .park(from: nil)) : nil
    }

    private func showsAnyTab(of windowId: CGWindowID) -> Bool {
        windowSystem.showsAny(Set(workspaces.tabGroupMembers(of: windowId)))
    }

    private func place(_ windowId: CGWindowID, parked: Bool) {
        place([(windowId: windowId, parked: parked)])
    }

    @discardableResult
    private func place(_ placements: [(windowId: CGWindowID, parked: Bool)]) -> [FrameOutcome] {
        apply(placements.compactMap(request(for:)))
    }

    private func apply(_ requests: [FrameRequest]) -> [FrameOutcome] {
        let outcomes = desktop.reframe(requests)
        parkedWindows.record(outcomes)
        layouts.record(outcomes, on: desktop.display.id)
        return outcomes
    }
}
