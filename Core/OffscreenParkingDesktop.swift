import AppKit
import CoreGraphics

final class OffscreenParkingDesktop: Desktop {
    private struct Move {
        let windowId: CGWindowID
        let window: any Window
        let change: FrameChange
    }

    private static let filledTolerance: CGFloat = 30

    private let screen: ScreenGeometry
    private let inset: CGFloat
    private let hiddenEdge: HiddenEdge
    private let window: (CGWindowID) -> (any Window)?
    private let notificationCenter: NotificationCenter

    private var nativeSpaceChangeObserver: (any NSObjectProtocol)?

    init(
        screen: ScreenGeometry,
        window: @escaping (CGWindowID) -> (any Window)?,
        inset: CGFloat = 15,
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.screen = screen
        self.inset = inset
        hiddenEdge = HiddenEdge(screen: screen)
        self.window = window
        self.notificationCenter = notificationCenter
    }

    func recover(_ windows: [WindowSnapshot]) -> [WindowSnapshot] {
        windows.map { snapshot in
            guard !snapshot.isMinimized, hiddenEdge.holds(snapshot.frame),
                  let win = window(snapshot.id)
            else { return snapshot }

            Log.desktop.info("recovering \(snapshot.logDescription) stuck at hidden edge")
            let recovered = centered(snapshot.frame.size)
            move(win, from: snapshot.frame, to: recovered)
            return snapshot.moved(to: recovered)
        }
    }

    func reframe(_ changes: [(windowId: CGWindowID, change: FrameChange)]) -> [FrameOutcome] {
        var outcomes: [FrameOutcome] = []
        var moves: [Move] = []

        for (windowId, change) in changes {
            guard let win = window(windowId) else {
                Log.desktop.info("cannot \(change.logDescription) id=\(windowId): window not found")
                outcomes.append(.gone(windowId))
                continue
            }

            moves.append(Move(windowId: windowId, window: win, change: change))
        }

        return outcomes + Concurrently.map(over: Array(Dictionary(grouping: moves, by: \.window.pid).values)) {
            $0.map(apply)
        }
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

    func repark(_ parked: [(windowId: CGWindowID, parkedFrom: CGRect)]) {
        for (windowId, parkedFrom) in parked {
            guard let win = window(windowId),
                  let frame = win.movableFrame(),
                  !hiddenEdge.holds(frame)
            else { continue }

            let hidden = hiddenEdge.frame(parking: parkedFrom)
            move(win, from: frame, to: hidden)
            Log.desktop.info("re-hid id=\(windowId) pulled back to \(frame), to=\(hidden)")
        }
    }

    private func apply(_ requested: Move) -> FrameOutcome {
        guard let current = requested.window.movableFrame() else {
            Log.desktop.info("cannot \(requested.change.logDescription) id=\(requested.windowId): window not movable")
            if case let .unpark(parkedFrom?) = requested.change { return .parked(requested.windowId, from: parkedFrom) }
            return .active(requested.windowId)
        }

        let (target, outcome) = destination(current, for: requested)
        if target != current {
            move(requested.window, from: current, to: target)
            Log.desktop.debug("\(requested.change.logDescription) id=\(requested.windowId) from=\(current) to=\(target)")
        }
        return outcome
    }

    private func destination(_ current: CGRect, for requested: Move) -> (frame: CGRect, outcome: FrameOutcome) {
        switch requested.change {
        case .park:
            let onScreen = onScreenFrame(for: requested.windowId, replacing: current)
            return (hiddenEdge.frame(parking: onScreen), .parked(requested.windowId, from: onScreen))
        case let .unpark(parkedFrom):
            return (onScreenFrame(for: requested.windowId, replacing: parkedFrom ?? current), .active(requested.windowId))
        case let .step(step):
            return (step.frame(moving: current, within: screen.visibleFrame), .active(requested.windowId))
        case .center:
            return (centered(current.size), .active(requested.windowId))
        case let .maximize(restoring):
            if let restoring { return (restoring, .active(requested.windowId)) }
            let filled = screen.visibleFrame.insetBy(dx: inset, dy: inset)
            guard !fills(current, filled) else {
                Log.desktop.info("id=\(requested.windowId) already fills the screen, no frame to go back to")
                return (current, .active(requested.windowId))
            }
            return (filled, .maximized(requested.windowId, from: current))
        }
    }

    /// A window rarely settles at the size it was given: Terminal quantizes its height to
    /// whole rows, which at a large font size is tens of points. A window this close to the
    /// filled frame is maximized, and the frame it stands at must not be recorded as the
    /// one to go back to: taking it there would leave it filled.
    private func fills(_ current: CGRect, _ filled: CGRect) -> Bool {
        abs(current.minX - filled.minX) <= Self.filledTolerance
            && abs(current.minY - filled.minY) <= Self.filledTolerance
            && abs(current.maxX - filled.maxX) <= Self.filledTolerance
            && abs(current.maxY - filled.maxY) <= Self.filledTolerance
    }

    private func centered(_ size: CGSize) -> CGRect {
        let bounds = screen.visibleFrame

        return CGRect(
            x: bounds.minX + (bounds.width - size.width) / 2,
            y: bounds.minY + (bounds.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    private func onScreenFrame(for windowId: CGWindowID, replacing frame: CGRect) -> CGRect {
        guard hiddenEdge.holds(frame) else { return frame }

        let recovered = centered(frame.size)
        Log.desktop.info("id=\(windowId) frame \(frame) sits at the hidden edge, taking \(recovered) instead")
        return recovered
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
