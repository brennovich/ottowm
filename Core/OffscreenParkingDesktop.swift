import AppKit
import CoreGraphics

/// Applies `Placement` on one macOS Space, like AeroSpace. A parked window is moved to
/// the bottom-right corner, and restored to its captured frame on the next switch.
final class OffscreenParkingDesktop: Desktop {
    /// One window's move, decided on the main thread and carried out off it.
    private struct Move {
        let windowId: CGWindowID
        let window: any Window
        let placement: Placement
        /// The frame the window is owed back, when it is already parked.
        let parkedFrom: CGRect?
    }

    private let hiddenEdge: HiddenEdge
    private let window: (CGWindowID) -> (any Window)?
    private let notificationCenter: NotificationCenter

    private var nativeSpaceChangeObserver: (any NSObjectProtocol)?

    init(
        screen: ScreenGeometry,
        window: @escaping (CGWindowID) -> (any Window)?,
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        hiddenEdge = HiddenEdge(screen: screen)
        self.window = window
        self.notificationCenter = notificationCenter
    }

    /// Moves the windows found parked at the hidden edge back on screen.
    /// - Returns: the windows at their current frames. A recovered one has moved, and the
    ///   model records where it ended up.
    func recover(_ windows: [WindowSnapshot]) -> [WindowSnapshot] {
        windows.map { snapshot in
            guard !snapshot.isMinimized, hiddenEdge.holds(snapshot.frame),
                  let win = window(snapshot.id)
            else { return snapshot }

            Log.desktop.info("recovering \(snapshot.logDescription) stuck at hidden edge")
            let recovered = hiddenEdge.recovered(from: snapshot.frame)
            move(win, from: snapshot.frame, to: recovered)
            return snapshot.moved(to: recovered)
        }
    }

    func place(_ placements: [(windowId: CGWindowID, placement: Placement, owedFrame: CGRect?)]) -> [PlacementOutcome] {
        var outcomes: [PlacementOutcome] = []
        var moves: [Move] = []

        for (windowId, placement, owedFrame) in placements {
            // A quitting application drops its windows without a destroyed notification
            // for each. Without this the model keeps placing them on every switch.
            guard let win = window(windowId) else {
                Log.desktop.info("cannot move id=\(windowId) to \(placement): window not found")
                outcomes.append(.gone(windowId))
                continue
            }
            // An already parked window is left where it is, without a frame read.
            guard placement != .parked || owedFrame == nil else { continue }

            moves.append(Move(windowId: windowId, window: win, placement: placement, parkedFrom: owedFrame))
        }

        return outcomes + carryOut(moves)
    }

    @discardableResult
    func move(_ windowId: CGWindowID, _ step: Step) -> Bool {
        guard let win = window(windowId) else {
            Log.desktop.info("cannot move id=\(windowId) \(step.direction.rawValue): window not found")
            return false
        }
        guard let current = win.movableFrame() else {
            Log.desktop.info("cannot move id=\(windowId) \(step.direction.rawValue): window not movable")
            return true
        }

        let target = step.frame(moving: current, within: hiddenEdge.screen.visibleFrame)
        move(win, from: current, to: target)
        Log.desktop.debug("moved id=\(windowId) \(step.direction.rawValue) from=\(current) to=\(target)")
        return true
    }

    func focus(_ windowId: CGWindowID) -> Bool {
        guard let win = window(windowId) else {
            Log.desktop.debug("cannot focus id=\(windowId): window not found")
            return false
        }
        win.focus()
        return true
    }

    func startWatching(nativeSpaceChange callback: @escaping () -> Void) {
        stopWatching()
        nativeSpaceChangeObserver = notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: nil
        ) { _ in
            callback()
        }
    }

    func repark(_ parked: [(windowId: CGWindowID, owedFrame: CGRect)]) {
        for (windowId, owedFrame) in parked {
            guard let win = window(windowId),
                  let frame = win.movableFrame(),
                  !hiddenEdge.holds(frame)
            else { continue }

            let hidden = hiddenEdge.frame(parking: owedFrame)
            move(win, from: frame, to: hidden)
            Log.desktop.info("re-hid id=\(windowId) pulled back to \(frame), to=\(hidden)")
        }
    }

    /// No window belongs at the corner, so a frame sitting there is replaced by an
    /// on-screen one. This keeps a window from being parked at a corner frame, or restored
    /// to one.
    private func onScreenFrame(for windowId: CGWindowID, replacing frame: CGRect) -> CGRect {
        guard hiddenEdge.holds(frame) else { return frame }

        let recovered = hiddenEdge.recovered(from: frame)
        Log.desktop.info("id=\(windowId) frame \(frame) sits at the hidden edge, taking \(recovered) instead")
        return recovered
    }

    /// An accessibility call blocks until the application it addresses answers, so moves
    /// of different applications overlap. The ones of a single application stay in one
    /// group, in the order they were asked for: they would queue behind each other anyway.
    private func carryOut(_ moves: [Move]) -> [PlacementOutcome] {
        Concurrently.map(over: Array(Dictionary(grouping: moves, by: \.window.pid).values)) {
            $0.map(run)
        }
    }

    /// Runs off the main thread. It reads and writes the window it was given and nothing
    /// else, and hands the model back what to record.
    private func run(_ requested: Move) -> PlacementOutcome {
        guard let currentFrame = requested.window.movableFrame() else {
            Log.desktop.info("cannot move id=\(requested.windowId) to \(requested.placement): window not movable")
            guard let parkedFrom = requested.parkedFrom else { return .activated(requested.windowId) }
            return .parked(requested.windowId, owing: parkedFrom)
        }

        switch requested.placement {
        case .parked:
            let originalFrame = onScreenFrame(for: requested.windowId, replacing: currentFrame)
            let hidden = hiddenEdge.frame(parking: originalFrame)
            move(requested.window, from: currentFrame, to: hidden)
            Log.desktop.debug("hid id=\(requested.windowId) from=\(currentFrame) to=\(hidden)")
            return .parked(requested.windowId, owing: originalFrame)
        case .active:
            let target = onScreenFrame(for: requested.windowId, replacing: requested.parkedFrom ?? currentFrame)
            if target != currentFrame {
                move(requested.window, from: currentFrame, to: target)
                Log.desktop.debug("restored id=\(requested.windowId) to=\(target)")
            }
            return .activated(requested.windowId)
        }
    }

    private func move(_ win: any Window, from current: CGRect, to target: CGRect) {
        win.withoutAnimations {
            if current.origin != target.origin { win.setPosition(target.origin) }
            if current.size != target.size { win.setSize(target.size) }
        }
    }

    private func stopWatching() {
        if let nativeSpaceChangeObserver {
            notificationCenter.removeObserver(nativeSpaceChangeObserver)
            self.nativeSpaceChangeObserver = nil
        }
    }

    deinit {
        stopWatching()
    }
}
