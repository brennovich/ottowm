import CoreGraphics

/// The slots of an `arrange tall`: a main window beside a stack column, as in dwm and xmonad.
struct Tall: Codable, Equatable {
    static let defaultRatio: CGFloat = 0.6

    var windowIds: [CGWindowID]
    private(set) var ratio: CGFloat
    private(set) var stackShares: [CGFloat]
    /// The slot the main window was swapped in from, which a swap of the main window toward
    /// the stack goes back to.
    private(set) var mainCameFrom: Int?

    init(
        windowIds: [CGWindowID],
        ratio: CGFloat = Tall.defaultRatio,
        stackShares: [CGFloat]? = nil,
        mainCameFrom: Int? = nil
    ) {
        let stackCount = max(windowIds.count - 1, 0)
        self.windowIds = windowIds
        self.ratio = ratio
        self.stackShares = stackShares ?? Array(repeating: 1 / CGFloat(stackCount), count: stackCount)
        self.mainCameFrom = mainCameFrom
    }

    init(main: CGWindowID, others: [CGWindowID: CGRect]) {
        let stack = others
            .sorted { ($0.value.midY, $0.value.midX, $0.key) < ($1.value.midY, $1.value.midX, $1.key) }
            .map(\.key)
        self.init(windowIds: [main] + stack)
    }

    func slots(within bounds: CGRect, gap: CGFloat) -> [CGRect] {
        guard !stackShares.isEmpty else { return [bounds] }

        let mainWidth = (bounds.width - gap) * ratio
        let stackX = bounds.minX + mainWidth + gap
        let stackWidth = bounds.maxX - stackX
        let stackHeight = stackHeight(within: bounds, gap: gap)

        var y = bounds.minY
        let stack = stackShares.map { share in
            let slot = CGRect(x: stackX, y: y, width: stackWidth, height: stackHeight * share)
            y = slot.maxY + gap
            return slot
        }

        return [CGRect(x: bounds.minX, y: bounds.minY, width: mainWidth, height: bounds.height)] + stack
    }

    /// Moves the edge the window shares with its neighbour: the main and stack columns for a
    /// width change, the next stack window below for a height change, or above for the bottom one.
    /// - Returns: `nil` when the window has no such neighbour.
    func resizing(_ windowId: CGWindowID, _ resize: Resize, within bounds: CGRect, gap: CGFloat) -> Tall? {
        guard let index = windowIds.firstIndex(of: windowId), !stackShares.isEmpty else { return nil }
        let grown = resize.change == .wider || resize.change == .taller ? resize.points : -resize.points

        var resized = self
        switch resize.change {
        case .wider, .narrower:
            resized.ratio += (index == 0 ? grown : -grown) / (bounds.width - gap)
        case .taller, .shorter:
            guard index > 0, stackShares.count > 1 else { return nil }
            let own = index - 1
            let neighbour = own + 1 < stackShares.count ? own + 1 : own - 1
            let moved = grown / stackHeight(within: bounds, gap: gap)
            resized.stackShares[own] += moved
            resized.stackShares[neighbour] -= moved
        }
        return resized
    }

    /// Moves the edges so each window gets at least its minimum size: a window held at its
    /// minimum height gives the rest of the column to the others, by their shares. A window
    /// with no known minimum keeps at least `floor`.
    /// A tall that fits is returned as it is: recomputing its edges can move them by a rounding error.
    /// - Returns: `nil` when the minimums do not fit.
    func fitted(to minimums: [CGWindowID: CGSize], within bounds: CGRect, gap: CGFloat, floor: CGFloat) -> Tall? {
        guard !stackShares.isEmpty, !fits(minimums, within: bounds, gap: gap, floor: floor) else { return self }
        let stack = Array(windowIds.dropFirst())

        let width = bounds.width - gap
        let mainMinimum = minimum(of: windowIds[0], minimums, floor: floor)
        let stackMinimum = stack.map { minimum(of: $0, minimums, floor: floor).width }.max() ?? floor
        guard mainMinimum.width + stackMinimum <= width, mainMinimum.height <= bounds.height else { return nil }
        let mainWidth = min(max(width * ratio, mainMinimum.width), width - stackMinimum)

        let height = stackHeight(within: bounds, gap: gap)
        let floors = stack.map { minimum(of: $0, minimums, floor: floor).height }
        guard floors.reduce(0, +) <= height else { return nil }

        var held = Set<Int>()
        var heights = floors
        while true {
            let free = height - held.map { floors[$0] }.reduce(0, +)
            let others = stackShares.indices.filter { !held.contains($0) }
            let weight = others.map { stackShares[$0] }.reduce(0, +)
            for index in others { heights[index] = free * stackShares[index] / weight }

            let below = others.filter { heights[$0] < floors[$0] }
            guard !below.isEmpty else { break }
            for index in below { heights[index] = floors[index] }
            held.formUnion(below)
        }

        var fitted = self
        fitted.ratio = mainWidth / width
        fitted.stackShares = heights.map { $0 / height }
        return fitted
    }

    /// Whether each slot holds the minimum size of its window, and at least `floor` on each side.
    func fits(_ minimums: [CGWindowID: CGSize], within bounds: CGRect, gap: CGFloat, floor: CGFloat) -> Bool {
        zip(windowIds, slots(within: bounds, gap: gap)).allSatisfy { windowId, slot in
            let minimum = minimum(of: windowId, minimums, floor: floor)
            return slot.width >= minimum.width && slot.height >= minimum.height
        }
    }

    /// Trades slots with the window `direction` leads to. The main window only goes east, to
    /// the slot it came from when it was swapped in.
    func swapping(_ windowId: CGWindowID, _ direction: Direction, within bounds: CGRect, gap: CGFloat) -> Tall? {
        guard let index = windowIds.firstIndex(of: windowId), index > 0 || direction == .east,
              let target = (index == 0 ? mainCameFrom : nil) ?? nearest(to: index, direction, within: bounds, gap: gap)
        else { return nil }

        var swapped = self
        swapped.windowIds.swapAt(index, target)
        swapped.mainCameFrom = index == 0 ? target : target == 0 ? index : mainCameFrom
        return swapped
    }

    /// The height of the stack column left after the gaps between its windows.
    private func stackHeight(within bounds: CGRect, gap: CGFloat) -> CGFloat {
        bounds.height - gap * CGFloat(stackShares.count - 1)
    }

    private func minimum(of windowId: CGWindowID, _ minimums: [CGWindowID: CGSize], floor: CGFloat) -> CGSize {
        let known = minimums[windowId] ?? .zero
        return CGSize(width: max(known.width, floor), height: max(known.height, floor))
    }

    private func nearest(to index: Int, _ direction: Direction, within bounds: CGRect, gap: CGFloat) -> Int? {
        let slots = slots(within: bounds, gap: gap)
        let others = Dictionary(uniqueKeysWithValues: slots.indices.filter { $0 != index }.map { (CGWindowID($0), slots[$0]) })
        return Neighbors(around: slots[index], among: others).nearest(to: direction).map(Int.init)
    }
}
