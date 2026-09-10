import AppKit
import CoreGraphics

final class OffscreenParkingDesktop: Desktop {
    private struct Move {
        let windowId: CGWindowID
        let window: any Window
        let change: FrameChange
    }

    private static let filledTolerance: CGFloat = 30

    private let screens: any Screens
    private let inset: CGFloat
    private let window: (CGWindowID) -> (any Window)?
    private let notificationCenter: NotificationCenter
    private let screenNotificationCenter: NotificationCenter

    private(set) var display: Display
    private var hiddenEdge: HiddenEdge
    private var observers: [(center: NotificationCenter, token: any NSObjectProtocol)] = []

    init(
        screens: any Screens,
        window: @escaping (CGWindowID) -> (any Window)?,
        inset: CGFloat = 15,
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        screenNotificationCenter: NotificationCenter = .default
    ) {
        self.screens = screens
        self.inset = inset
        display = screens.main ?? Display(id: DisplayID(rawValue: "none"), fullFrame: .zero, visibleFrame: .zero)
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

    func startWatching(_ handler: @escaping (DesktopEvent) -> Void) {
        stopWatching()
        observers = [
            (notificationCenter, notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: nil
            ) { _ in handler(.nativeSpaceChange) }),
            (screenNotificationCenter, screenNotificationCenter.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: nil
            ) { [weak self] _ in self?.screenParametersChanged(handler) }),
        ]
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
            switch requested.change {
            case let .unpark(parkedFrom?), let .park(from: parkedFrom?): return .parked(requested.windowId, from: parkedFrom)
            case let .maximize(restoring?), let .fill(_, restoring?): return .filled(requested.windowId, from: restoring)
            case .step, .resize, .center, .park, .unpark, .maximize, .fill: return .active(requested.windowId)
            }
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
        case let .park(from: known):
            let onScreen = onScreenFrame(for: requested.windowId, replacing: known ?? current)
            return (hiddenEdge.frame(parking: onScreen), .parked(requested.windowId, from: onScreen))
        case let .unpark(parkedFrom):
            return (onScreenFrame(for: requested.windowId, replacing: parkedFrom ?? current), .active(requested.windowId))
        case let .step(step):
            return (step.frame(moving: current, within: display.visibleFrame), .active(requested.windowId))
        case let .resize(resize):
            return (resize.frame(resizing: current, within: display.visibleFrame), .active(requested.windowId))
        case .center:
            return (centered(current.size), .active(requested.windowId))
        case let .maximize(restoring):
            return destination(current, filling: filled, restoring: restoring, of: requested.windowId)
        case let .fill(direction, restoring):
            let half = Half(direction: direction).frame(within: filled, gap: inset)
            return destination(current, filling: half, restoring: restoring, of: requested.windowId)
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
        display.visibleFrame.insetBy(dx: inset, dy: inset)
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
    /// once per plug, so only a display that differs from the one held is reported.
    private func screenParametersChanged(_ handler: (DesktopEvent) -> Void) {
        let main = screens.main
        Log.desktop.debug("screen parameters changed, main display: \(main.map(\.logDescription) ?? "none")")
        guard let entered = main, entered != display else { return }

        let left = display
        display = entered
        hiddenEdge = HiddenEdge(display: entered)
        Log.desktop.info("display changed from \(left.logDescription) to \(entered.logDescription)")
        handler(.displayChange(from: left, to: entered))
    }

    private func stopWatching() {
        for (center, token) in observers { center.removeObserver(token) }
        observers = []
    }

    deinit {
        stopWatching()
    }
}
