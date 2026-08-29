import CoreGraphics

final class StubDesktop: Desktop {
    private let window: (CGWindowID) -> (any Window)?

    private(set) var placements: [CGWindowID: Placement] = [:]
    private(set) var placeCalls: [(windowId: CGWindowID, placement: Placement)] = []
    private(set) var placeBatches: [[CGWindowID]] = []
    private(set) var forgottenWindowIds: [CGWindowID] = []
    private(set) var moveCalls: [(windowId: CGWindowID, step: Step)] = []
    private(set) var recoverCount = 0
    private(set) var recoveredWindowIds: [CGWindowID] = []
    private(set) var manualNavigationCallback: ((CGWindowID) -> Void)?

    var recoveredFrames: [CGWindowID: CGRect] = [:]

    init(window: @escaping (CGWindowID) -> (any Window)? = { _ in nil }) {
        self.window = window
    }

    func recover(_ windows: [WindowSnapshot]) -> [WindowSnapshot] {
        recoverCount += 1
        recoveredWindowIds = windows.map(\.id)
        return windows.map { win in
            recoveredFrames[win.id].map { win.moved(to: $0) } ?? win
        }
    }

    @discardableResult
    func place(_ windowId: CGWindowID, at placement: Placement) -> Bool {
        placeCalls.append((windowId: windowId, placement: placement))
        placements[windowId] = placement
        return true
    }

    @discardableResult
    func place(_ placements: [(windowId: CGWindowID, placement: Placement)]) -> [CGWindowID] {
        placeBatches.append(placements.map(\.windowId))
        return placements.compactMap { place($0.windowId, at: $0.placement) ? nil : $0.windowId }
    }

    var missingWindowIds: Set<CGWindowID> = []

    /// Applies the step without bounds, which is `Step`'s and the real desktop's job.
    @discardableResult
    func move(_ windowId: CGWindowID, _ step: Step) -> Bool {
        guard !missingWindowIds.contains(windowId), let win = window(windowId) else { return false }

        moveCalls.append((windowId: windowId, step: step))
        win.withoutAnimations {
            win.setPosition(step.frame(moving: win.snapshot().frame, within: .infinite).origin)
        }
        return true
    }

    func clearPlaceCalls() {
        placeCalls = []
        placeBatches = []
    }

    func restoreAll() {
        for (windowId, placement) in placements where placement == .storage {
            place(windowId, at: .active)
        }
    }

    func placement(of windowId: CGWindowID) -> Placement {
        placements[windowId] ?? .active
    }

    func focus(_ windowId: CGWindowID) -> Bool {
        guard let win = window(windowId) else { return false }
        win.focus()
        return true
    }

    func startWatching(manualNavigation callback: @escaping (CGWindowID) -> Void) {
        manualNavigationCallback = callback
    }

    func forget(_ windowId: CGWindowID) {
        forgottenWindowIds.append(windowId)
        placements[windowId] = nil
    }
}
