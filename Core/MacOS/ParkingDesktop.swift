import AppKit
import CoreGraphics

final class ParkingDesktop: Desktop {
    private struct Move {
        let request: FrameRequest
        let window: any Window
    }

    private let screens: any Screens
    var spacing: CGFloat
    private let window: (CGWindowID) -> (any Window)?
    private let notificationCenter: NotificationCenter
    private let screenNotificationCenter: NotificationCenter

    private(set) var display: Display

    private var observers: [(center: NotificationCenter, token: any NSObjectProtocol)] = []
    private var handlers: [(DesktopEvent) -> Void] = []
    private var workArea: WorkArea { WorkArea(display: display, spacing: spacing) }

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
        self.window = window
        self.notificationCenter = notificationCenter
        self.screenNotificationCenter = screenNotificationCenter
    }

    func recover(_ windows: [WindowSnapshot]) -> [WindowSnapshot] {
        windows.map { snapshot in
            let recovered = workArea.onScreen(snapshot.frame)
            guard !snapshot.isMinimized, recovered != snapshot.frame, let win = window(snapshot.id)
            else { return snapshot }

            Log.desktop.info("recovering \(snapshot.logDescription) stuck at hidden edge")
            win.withoutAnimations { move(win, from: snapshot.frame, to: recovered) }
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

        let batches = Array(Dictionary(grouping: moves, by: \.window.pid).values)
        return outcomes + Concurrently.map(batches, apply).flatMap { $0 }
    }

    func isMaximized(_ frame: CGRect) -> Bool {
        workArea.fills(frame, workArea.filled)
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
                  !workArea.hiddenEdge.holds(frame)
            else { continue }

            let hidden = workArea.hiddenEdge.frame(parking: parkedFrom)
            win.withoutAnimations { move(win, from: frame, to: hidden) }
            Log.desktop.info("re-hid id=\(windowId) pulled back to \(frame), to=\(hidden)")
        }
    }

    /// `AXEnhancedUserInterface` belongs to the application, so one batch of its windows turns
    /// it off once.
    private func apply(_ batch: [Move]) -> [FrameOutcome] {
        guard let first = batch.first else { return [] }

        return first.window.withoutAnimations { batch.map(apply) }
    }

    private func apply(_ requested: Move) -> FrameOutcome {
        let request = requested.request
        guard let current = requested.window.movableFrame() else {
            Log.desktop.info("cannot \(request.change.logDescription) id=\(request.windowId): window not movable")
            return request.knownOutcome
        }

        let (target, outcome) = workArea.frame(request, from: current)
        if target != current {
            move(requested.window, from: current, to: target)
            Log.desktop.debug("\(request.change.logDescription) id=\(request.windowId) from=\(current) to=\(target)")
        }
        return outcome
    }

    private func move(_ win: any Window, from current: CGRect, to target: CGRect) {
        if current.origin != target.origin { win.setPosition(target.origin) }
        if current.size != target.size { win.setSize(target.size) }
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
