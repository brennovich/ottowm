import CoreGraphics

/// The `arrange tall` of the current workspace. It is applied once: no window event updates it.
/// While every arranged window still stands in its slot, the arrangement is intact, and a
/// resize, a move or a maximize of an arranged window changes the arrangement instead of the
/// window alone.
final class ArrangedWindows {
    private let desktop: any Desktop
    private let windowSystem: WindowSystem
    private let workspaces: Workspaces
    private let placement: WindowPlacement
    private let log: LogChannel

    /// The smallest size each window kept when given a smaller slot. The AX API does not
    /// report a minimum size, so it is learned from the windows that refuse one.
    private var minimumSizes: [CGWindowID: CGSize] = [:]

    init(
        desktop: any Desktop,
        windowSystem: WindowSystem,
        workspaces: Workspaces,
        placement: WindowPlacement,
        log: LogChannel = Log.engine
    ) {
        self.desktop = desktop
        self.windowSystem = windowSystem
        self.workspaces = workspaces
        self.placement = placement
        self.log = log
    }

    /// Puts every window of an intact arrangement back where it was before, else arranges the
    /// windows on screen around `focused`.
    func arrange(around focused: WindowSnapshot) {
        let current = workspaces.current

        if let intact = intact() {
            log.info("restoring the arrangement of workspace \(current)")
            restore(intact)
            return
        }

        let others = workspaces.windowIds(in: current).filter { $0 != focused.id && !placement.isParked($0) }
        let tall = Tall(main: focused.id, others: windowSystem.frames(of: others))
        log.info("arranging workspace \(current) tall: \(tall.windowIds)")

        // Each pass that moves a window learns a minimum size, so a pass per window is enough.
        let workArea = desktop.workArea
        var placed: Tall?
        for _ in 0 ... tall.windowIds.count {
            guard let fitted = tall.fitted(to: minimumSizes, within: workArea.filled, gap: workArea.spacing, floor: floor)
            else {
                log.info("arrange dropped: the minimum sizes of the windows do not fit the screen")
                if let placed { restore(placed) }
                return
            }

            workspaces.arrange(fitted, in: current)
            if place(fitted, replacing: placed) { return }
            placed = fitted
        }
    }

    func resize(_ focused: WindowSnapshot, _ change: Resize.Change) -> Bool {
        changeArrangement(of: focused, "resize \(change.rawValue)") { tall, workArea in
            let resize = Resize(change: change, points: workArea.spacing)
            return tall.resizing(focused.id, resize, within: workArea.filled, gap: workArea.spacing)
        }
    }

    func swap(_ focused: WindowSnapshot, _ direction: Direction) -> Bool {
        changeArrangement(of: focused, "swap \(direction.rawValue)") { tall, workArea in
            tall.swapping(focused.id, direction, within: workArea.filled, gap: workArea.spacing)
        }
    }

    /// - Returns: `false` unless the window is maximized out of an intact arrangement, which
    ///   leaves the maximize to restore the window alone.
    func returnToSlot(_ focused: WindowSnapshot) -> Bool {
        guard desktop.isMaximized(focused.frame),
              let tall = intact(ignoring: focused.id), tall.windowIds.count > 1,
              let index = tall.windowIds.firstIndex(of: focused.id)
        else { return false }

        placement.reframe([FrameRequest(windowId: focused.id, change: .arrange(into: slots(of: tall)[index]))])
        return true
    }

    /// The arrangement of the current workspace when each window, or a tab of its group, stands
    /// in its slot. The tab shown takes the place of the window recorded.
    private func intact(ignoring ignored: CGWindowID? = nil) -> Tall? {
        let current = workspaces.current
        guard let tall = workspaces.arranged(in: current) else { return nil }

        let workArea = desktop.workArea
        var shown: [CGWindowID] = []
        for (windowId, slot) in zip(tall.windowIds, slots(of: tall)) {
            let tabs = workspaces.tabGroupMembers(of: windowId)
                .filter { workspaces.workspace(for: $0) == current && !placement.isParked($0) }
            guard let (tabId, frame) = windowSystem.frames(of: tabs).first,
                  tabId == ignored || workArea.fills(frame, slot)
            else { return nil }

            shown.append(tabId)
        }

        var intact = tall
        intact.windowIds = shown
        return intact
    }

    /// Records the change and moves the windows whose slot changed. A change is dropped when a
    /// slot is smaller than a known minimum size, and undone when a window keeps a size larger
    /// than its new slot: the window would cover its neighbour.
    /// - Returns: `false` when the window is not part of an intact arrangement, which leaves
    ///   the action to the window alone.
    private func changeArrangement(of focused: WindowSnapshot, _ action: String, _ change: (Tall, WorkArea) -> Tall?) -> Bool {
        guard let tall = intact(), tall.windowIds.contains(focused.id) else { return false }

        let workArea = desktop.workArea
        guard let changed = change(tall, workArea) else {
            log.info("\(action) dropped: no arranged window that way")
            return true
        }
        guard changed.fits(minimumSizes, within: workArea.filled, gap: workArea.spacing, floor: floor) else {
            log.info("\(action) dropped: a slot is smaller than the minimum size of its window")
            return true
        }

        workspaces.arrange(changed, in: workspaces.current)
        if place(changed, replacing: tall) { return true }

        log.info("\(action) undone")
        workspaces.arrange(tall, in: workspaces.current)
        place(tall, replacing: changed)
        return true
    }

    private func restore(_ tall: Tall) {
        workspaces.arrange(nil, in: workspaces.current)
        placement.reframe(tall.windowIds.compactMap { windowId in
            placement.originalFrame(of: windowId).map { FrameRequest(windowId: windowId, change: .restore($0)) }
        })
    }

    /// - Returns: whether every window took its slot.
    @discardableResult
    private func place(_ tall: Tall, replacing previous: Tall?) -> Bool {
        let before = previous.map { Dictionary(uniqueKeysWithValues: zip($0.windowIds, slots(of: $0))) } ?? [:]
        let after = zip(tall.windowIds, slots(of: tall))
        let requests = after.compactMap { windowId, slot in
            before[windowId] == slot ? nil : FrameRequest(windowId: windowId, change: .arrange(into: slot))
        }
        return learnMinimumSizes(from: placement.reframe(requests), slots: Dictionary(uniqueKeysWithValues: after))
    }

    /// Records the size a moved window kept on each side where it is larger than its slot.
    /// Only a window that was larger than its slot before the move is read: a read right after
    /// a size write waits for the application's relayout, 10-30ms a window. The frame is read
    /// from the window, not from the on-screen list: that list is read once per operation,
    /// before the move.
    /// - Returns: whether every window took its slot.
    private func learnMinimumSizes(from outcomes: [FrameOutcome], slots: [CGWindowID: CGRect]) -> Bool {
        var tookSlots = true
        for case let .filled(windowId, from) in outcomes {
            guard let slot = slots[windowId], sides(of: from, largerThan: slot) != .zero,
                  let frame = windowSystem.frame(of: windowId)
            else { continue }

            let kept = sides(of: frame, largerThan: slot)
            guard kept != .zero else { continue }

            let known = minimumSizes[windowId] ?? .zero
            minimumSizes[windowId] = CGSize(width: max(known.width, kept.width), height: max(known.height, kept.height))
            log.info("id=\(windowId) keeps \(frame.width)x\(frame.height), larger than its slot")
            tookSlots = false
        }
        return tookSlots
    }

    /// The width and height of `frame` where they exceed the slot's, else 0. 1pt of room is
    /// left because the window server rounds a fractional slot size.
    private func sides(of frame: CGRect, largerThan slot: CGRect) -> CGSize {
        CGSize(
            width: frame.width > slot.width + 1 ? frame.width : 0,
            height: frame.height > slot.height + 1 ? frame.height : 0
        )
    }

    /// The smallest side a slot keeps for a window with no known minimum size.
    private var floor: CGFloat {
        desktop.workArea.spacing * 4
    }

    private func slots(of tall: Tall) -> [CGRect] {
        let workArea = desktop.workArea
        return tall.slots(within: workArea.filled, gap: workArea.spacing)
    }
}
