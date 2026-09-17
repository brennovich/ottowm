import AppKit
import CoreGraphics

final class OffscreenParkingDesktop: Desktop {
    private struct Move {
        let request: FrameRequest
        let window: any Window
    }

    private static let filledTolerance: CGFloat = 30

    private let screens: any Screens
    var spacing: CGFloat
    private let window: (CGWindowID) -> (any Window)?
    private let notificationCenter: NotificationCenter
    private let screenNotificationCenter: NotificationCenter

    private(set) var display: Display
    private var hiddenEdge: HiddenEdge
    private var observers: [(center: NotificationCenter, token: any NSObjectProtocol)] = []
    private var handlers: [(DesktopEvent) -> Void] = []

    init(
        screens: any Screens,
        window: @escaping (CGWindowID) -> (any Window)?,
        spacing: CGFloat,
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        screenNotificationCenter: NotificationCenter = .default
    ) {
        self.screens = screens
        self.spacing = spacing
        display = screens.main ?? .unknown
        hiddenEdge = HiddenEdge(display: display)
        self.window = window
        self.notificationCenter = notificationCenter
        self.screenNotificationCenter = screenNotificationCenter
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

    func reframe(_ requests: [FrameRequest]) -> [FrameOutcome] {
        var outcomes: [FrameOutcome] = []
        var moves: [Move] = []

        for request in requests {
            guard let win = window(request.windowId) else {
                Log.desktop.info("cannot \(request.change.logDescription) id=\(request.windowId): window not found")
                outcomes.append(.gone(request.windowId))
                continue
            }

            moves.append(Move(request: request, window: win))
        }

        return outcomes + Concurrently.map(over: Array(Dictionary(grouping: moves, by: \.window.pid).values)) {
            $0.map(apply)
        }
    }

    func isMaximized(_ frame: CGRect) -> Bool {
        fills(frame, filled)
    }

    func focus(_ windowId: CGWindowID) -> Bool {
        guard let win = window(windowId) else {
            Log.desktop.debug("cannot focus id=\(windowId): window not found")
            return false
        }
        win.focus()
        return true
    }

    func startWatching(_ handler: @escaping (DesktopEvent) -> Void) {
        handlers.append(handler)
        guard observers.isEmpty else { return }

        observers = [
            (notificationCenter, notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: nil
            ) { [weak self] _ in self?.report(.nativeSpaceChange) }),
            (screenNotificationCenter, screenNotificationCenter.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: nil
            ) { [weak self] _ in self?.screenParametersChanged() }),
        ]
    }

    func repark(_ windows: [CGWindowID: CGRect]) {
        for (windowId, parkedFrom) in windows {
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
        let request = requested.request
        guard let current = requested.window.movableFrame() else {
            Log.desktop.info("cannot \(request.change.logDescription) id=\(request.windowId): window not movable")
            switch request.change {
            case let .unpark(parkedFrom?), let .park(from: parkedFrom?): return .parked(request.windowId, from: parkedFrom)
            case let .maximize(restoring?), let .tile(_, restoring?): return .filled(request.windowId, from: restoring)
            case .move, .resize, .center, .park, .unpark, .maximize, .tile: return .active(request.windowId)
            }
        }

        let (target, outcome) = destination(current, for: request)
        if target != current {
            move(requested.window, from: current, to: target)
            Log.desktop.debug("\(request.change.logDescription) id=\(request.windowId) from=\(current) to=\(target)")
        }
        return outcome
    }

    private func destination(_ current: CGRect, for request: FrameRequest) -> (frame: CGRect, outcome: FrameOutcome) {
        let windowId = request.windowId

        switch request.change {
        case let .park(from: known):
            let onScreen = onScreenFrame(for: windowId, replacing: known ?? current)
            return (hiddenEdge.frame(parking: onScreen), .parked(windowId, from: onScreen))
        case let .unpark(parkedFrom):
            return (onScreenFrame(for: windowId, replacing: parkedFrom ?? current), .active(windowId))
        case let .move(direction):
            let step = Step(direction: direction, points: spacing)
            return (step.frame(moving: current, within: display.visibleFrame), .active(windowId))
        case let .resize(change):
            let resize = Resize(change: change, points: spacing)
            return (resize.frame(resizing: current, within: display.visibleFrame), .active(windowId))
        case .center:
            return (centered(current.size), .active(windowId))
        case let .maximize(restoring):
            return destination(current, filling: filled, restoring: restoring, of: windowId)
        case let .tile(direction, restoring):
            let half = Half(direction: direction).frame(within: filled, gap: spacing)
            return destination(current, filling: half, restoring: restoring, of: windowId)
        }
    }

    /// A window already at the target is moved back to the frame it came from. Every
    /// target shares one record of that frame, so whether the window is filled is decided by
    /// its current frame, not by the presence of a record.
    private func destination(
        _ current: CGRect,
        filling target: CGRect,
        restoring: CGRect?,
        of windowId: CGWindowID
    ) -> (frame: CGRect, outcome: FrameOutcome) {
        guard fills(current, target) else { return (target, .filled(windowId, from: current)) }
        guard let restoring else {
            Log.desktop.info("id=\(windowId) already fills \(target), no frame to go back to")
            return (current, .active(windowId))
        }
        return (restoring, .active(windowId))
    }

    private var filled: CGRect {
        display.visibleFrame.insetBy(dx: spacing, dy: spacing)
    }

    /// Whether the window covers the target, within a tolerance.
    ///
    /// A window rarely settles at the size it was given: Terminal rounds its height to whole
    /// rows, tens of points at a large font size. The current frame of a window within the
    /// tolerance must not be recorded as the one to restore: restoring it would leave the
    /// window filled.
    private func fills(_ current: CGRect, _ target: CGRect) -> Bool {
        abs(current.minX - target.minX) <= Self.filledTolerance
            && abs(current.minY - target.minY) <= Self.filledTolerance
            && abs(current.maxX - target.maxX) <= Self.filledTolerance
            && abs(current.maxY - target.maxY) <= Self.filledTolerance
    }

    private func centered(_ size: CGSize) -> CGRect {
        let bounds = display.visibleFrame

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
        Log.desktop.info("id=\(windowId) frame \(frame) is at the hidden edge, taking \(recovered) instead")
        return recovered
    }

    private func move(_ win: any Window, from current: CGRect, to target: CGRect) {
        win.withoutAnimations {
            if current.origin != target.origin { win.setPosition(target.origin) }
            if current.size != target.size { win.setSize(target.size) }
        }
    }

    /// The notification also follows a Dock or menu bar change, and macOS posts it more than
    /// once per plug, so only a display that differs from the one held is reported as a
    /// display change.
    private func screenParametersChanged() {
        let main = screens.main
        Log.desktop.debug("screen parameters changed, main display: \(main.map(\.logDescription) ?? "none")")
        guard let entered = main else { return }
        guard entered != display else { return report(.screenParametersChange) }

        let left = display
        display = entered
        hiddenEdge = HiddenEdge(display: entered)
        Log.desktop.info("display changed from \(left.logDescription) to \(entered.logDescription)")
        report(.displayChange(DisplayChange(from: left, to: entered)))
    }

    private func report(_ event: DesktopEvent) {
        for handler in handlers { handler(event) }
    }

    deinit {
        for (center, token) in observers { center.removeObserver(token) }
    }
}
