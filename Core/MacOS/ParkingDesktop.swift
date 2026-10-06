import AppKit
import CoreGraphics

final class ParkingDesktop: Desktop {
    private struct Move {
        let request: FrameRequest
        let window: any Window
    }

    var spacing: CGFloat
    private let window: (CGWindowID) -> (any Window)?
    private let notificationCenter: NotificationCenter
    private let injectedAnchor: (any Anchor)?
    private(set) lazy var anchor: any Anchor = injectedAnchor ?? SpaceAnchor(log: log) { [weak self] in self?.display }
    private let log: LogChannel

    private(set) var display: Display

    private var observers: [(center: NotificationCenter, token: any NSObjectProtocol)] = []
    private var subscribers = Broadcast<DesktopEvent>()
    private var workArea: WorkArea { WorkArea(display: display, spacing: spacing) }

    init(
        display: Display,
        window: @escaping (CGWindowID) -> (any Window)?,
        spacing: CGFloat,
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        anchor: (any Anchor)? = nil,
        log: LogChannel = Log.desktop
    ) {
        self.spacing = spacing
        self.display = display
        self.window = window
        self.notificationCenter = notificationCenter
        injectedAnchor = anchor
        self.log = log
    }

    func recover(_ windows: [WindowSnapshot]) -> [WindowSnapshot] {
        windows.map { snapshot in
            let recovered = workArea.onScreen(snapshot.frame)
            guard !snapshot.isMinimized, recovered != snapshot.frame, let win = window(snapshot.id)
            else { return snapshot }

            log.info("recovering \(snapshot.logDescription) stuck at hidden edge")
            win.withoutAnimations { move(win, from: snapshot.frame, to: recovered) }
            return snapshot.moved(to: recovered)
        }
    }

    func reframe(_ requests: [FrameRequest]) -> [FrameOutcome] {
        var outcomes: [FrameOutcome] = []
        var moves: [Move] = []

        for request in requests {
            guard let win = window(request.windowId) else {
                log.info("cannot \(request.change.logDescription) id=\(request.windowId): window not found")
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
            log.debug("cannot focus id=\(windowId): window not found")
            return false
        }
        win.focus()
        return true
    }

    func startWatching(_ handler: @escaping (DesktopEvent) -> Void) {
        subscribers.watch(handler)
        guard observers.isEmpty else { return }

        observers = [
            (notificationCenter, notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: nil
            ) { [weak self] _ in self?.nativeSpaceChanged() }),
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
            log.info("re-hid id=\(windowId) pulled back to \(frame), to=\(hidden)")
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
            log.info("cannot \(request.change.logDescription) id=\(request.windowId): window not movable")
            return request.knownOutcome
        }

        let (target, outcome) = workArea.frame(request, from: current)
        if target != current {
            move(requested.window, from: current, to: target)
            log.debug("\(request.change.logDescription) id=\(request.windowId) from=\(current) to=\(target)")
        }
        return outcome
    }

    private func move(_ win: any Window, from current: CGRect, to target: CGRect) {
        if current.origin != target.origin { win.setPosition(target.origin) }
        if current.size != target.size { win.setSize(target.size) }
    }

    /// Put away first: a pin while the anchor is key orders it out with OttoWM active, and the
    /// focus then goes to the frontmost window on the Space, which can be parked.
    private func nativeSpaceChanged() {
        anchor.putAway()
        report(.nativeSpaceChange)
    }

    /// Only a display that differs from the one held is reported as a display change.
    func change(to entered: Display) {
        guard entered != display else { return report(.screenParametersChange) }

        let left = display
        display = entered
        log.notice("display changed from \(left.logDescription) to \(entered.logDescription)")
        report(.displayChange(DisplayChange(from: left, to: entered)))
    }

    private func report(_ event: DesktopEvent) {
        subscribers.report(event)
    }

    deinit {
        for (center, token) in observers { center.removeObserver(token) }
    }
}
