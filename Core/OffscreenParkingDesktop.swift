import AppKit
import CoreGraphics

/// Applies `Placement` on one macOS Space, like AeroSpace. A storage window is moved to
/// the bottom-right corner, and restored to its captured frame on the next switch.
final class OffscreenParkingDesktop: Desktop {
    /// The bottom-right sliver a parked window is moved to.
    struct HiddenEdge {
        private static let epsilon: CGFloat = 1
        private static let detectionMargin: CGFloat = 10

        let screen: ScreenGeometry

        func frame(parking windowFrame: CGRect) -> CGRect {
            CGRect(
                x: screen.fullFrame.maxX - Self.epsilon,
                y: screen.fullFrame.maxY - Self.epsilon,
                width: windowFrame.width,
                height: windowFrame.height
            )
        }

        func holds(_ frame: CGRect) -> Bool {
            frame.minX >= screen.fullFrame.maxX - Self.epsilon - Self.detectionMargin
        }

        func recovered(from windowFrame: CGRect) -> CGRect {
            let visibleFrame = screen.visibleFrame
            let width = min(windowFrame.width, visibleFrame.width)
            let height = min(windowFrame.height, visibleFrame.height)

            return CGRect(
                x: visibleFrame.minX + (visibleFrame.width - width) / 2,
                y: visibleFrame.minY + (visibleFrame.height - height) / 2,
                width: width,
                height: height
            )
        }
    }

    /// One window's move, decided on the main thread and carried out off it.
    private struct Move {
        let windowId: CGWindowID
        let window: any Window
        let placement: Placement
        /// The frame the window is owed back, when it is already parked.
        let parkedFrom: CGRect?
    }

    /// What a move leaves for the model: the frame the window is owed back, or `nil` once
    /// it is on screen.
    private struct Moved {
        let windowId: CGWindowID
        let parkedFrom: CGRect?
    }

    private let hiddenEdge: HiddenEdge
    private let window: (CGWindowID) -> (any Window)?
    private let focusedWindowId: () -> CGWindowID?
    private let notificationCenter: NotificationCenter

    private var hiddenWindowFrames: [CGWindowID: CGRect] = [:]
    private var manualNavigationObserver: (any NSObjectProtocol)?

    init(
        screen: ScreenGeometry,
        window: @escaping (CGWindowID) -> (any Window)?,
        focusedWindowId: @escaping () -> CGWindowID?,
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        hiddenEdge = HiddenEdge(screen: screen)
        self.window = window
        self.focusedWindowId = focusedWindowId
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

    @discardableResult
    func place(_ windowId: CGWindowID, at placement: Placement) -> Bool {
        place([(windowId: windowId, placement: placement)]).isEmpty
    }

    @discardableResult
    func place(_ placements: [(windowId: CGWindowID, placement: Placement)]) -> [CGWindowID] {
        var gone: [CGWindowID] = []
        var moves: [Move] = []

        for (windowId, placement) in placements {
            // A quitting application drops its windows without a destroyed notification
            // for each. Without this the model keeps placing them on every switch.
            guard let win = window(windowId) else {
                Log.desktop.info("cannot move id=\(windowId) to \(placement): window not found")
                gone.append(windowId)
                continue
            }
            // An already parked window is left where it is, without a frame read.
            guard placement != .storage || hiddenWindowFrames[windowId] == nil else { continue }

            moves.append(Move(
                windowId: windowId,
                window: win,
                placement: placement,
                parkedFrom: hiddenWindowFrames[windowId]
            ))
        }

        for moved in carryOut(moves) {
            hiddenWindowFrames[moved.windowId] = moved.parkedFrom
        }

        return gone
    }

    @discardableResult
    func move(_ windowId: CGWindowID, _ step: Step) -> Bool {
        guard let win = window(windowId) else {
            Log.desktop.info("cannot move id=\(windowId) \(step.direction.rawValue): window not found")
            return false
        }
        // A parked window is owed the frame recorded for it, not the one it sits at, so
        // moving it here would be undone by the next restore.
        guard hiddenWindowFrames[windowId] == nil else {
            Log.desktop.debug("move id=\(windowId) dropped: the window is parked")
            return true
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

    func restoreAll() {
        Log.desktop.info("restoring \(self.hiddenWindowFrames.count) parked windows")
        for windowId in hiddenWindowFrames.keys.sorted() {
            place(windowId, at: .active)
        }
    }

    func placement(of windowId: CGWindowID) -> Placement {
        hiddenWindowFrames[windowId] != nil ? .storage : .active
    }

    func focus(_ windowId: CGWindowID) -> Bool {
        guard let win = window(windowId) else {
            Log.desktop.debug("cannot focus id=\(windowId): window not found")
            return false
        }
        win.focus()
        return true
    }

    func startWatching(manualNavigation callback: @escaping (CGWindowID) -> Void) {
        stopWatching()
        manualNavigationObserver = notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.handleActiveSpaceChange(callback)
        }
    }

    func forget(_ windowId: CGWindowID) {
        hiddenWindowFrames[windowId] = nil
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
    private func carryOut(_ moves: [Move]) -> [Moved] {
        Concurrently.map(over: Array(Dictionary(grouping: moves, by: \.window.pid).values)) {
            $0.map(run)
        }
    }

    /// Runs off the main thread. It reads and writes the window it was given and nothing
    /// else, and hands the model back what to record.
    private func run(_ requested: Move) -> Moved {
        guard let currentFrame = requested.window.movableFrame() else {
            Log.desktop.info("cannot move id=\(requested.windowId) to \(requested.placement): window not movable")
            return Moved(windowId: requested.windowId, parkedFrom: requested.parkedFrom)
        }

        switch requested.placement {
        case .storage:
            let originalFrame = onScreenFrame(for: requested.windowId, replacing: currentFrame)
            let hidden = hiddenEdge.frame(parking: originalFrame)
            move(requested.window, from: currentFrame, to: hidden)
            Log.desktop.debug("hid id=\(requested.windowId) from=\(currentFrame) to=\(hidden)")
            return Moved(windowId: requested.windowId, parkedFrom: originalFrame)
        case .active:
            let target = onScreenFrame(for: requested.windowId, replacing: requested.parkedFrom ?? currentFrame)
            if target != currentFrame {
                move(requested.window, from: currentFrame, to: target)
                Log.desktop.debug("restored id=\(requested.windowId) to=\(target)")
            }
            return Moved(windowId: requested.windowId, parkedFrom: nil)
        }
    }

    private func move(_ win: any Window, from current: CGRect, to target: CGRect) {
        win.withoutAnimations {
            if current.origin != target.origin { win.setPosition(target.origin) }
            if current.size != target.size { win.setSize(target.size) }
        }
    }

    private func handleActiveSpaceChange(_ callback: (CGWindowID) -> Void) {
        guard let focusedId = focusedWindowId(), hiddenWindowFrames[focusedId] != nil else {
            Log.desktop.debug("native space change: no hidden window focused")
            // macOS moves the non-full-screen window back on screen when its full screen
            // instance exits, a Safari video for example.
            for (windowId, originalFrame) in hiddenWindowFrames {
                guard let win = window(windowId),
                      let frame = win.movableFrame(),
                      !hiddenEdge.holds(frame)
                else { continue }

                let hidden = hiddenEdge.frame(parking: originalFrame)
                move(win, from: frame, to: hidden)
                Log.desktop.info("re-hid id=\(windowId) pulled back to \(frame), to=\(hidden)")
            }
            return
        }
        Log.desktop.info("native space change with hidden window focused id=\(focusedId)")
        callback(focusedId)
    }

    private func stopWatching() {
        if let manualNavigationObserver {
            notificationCenter.removeObserver(manualNavigationObserver)
            self.manualNavigationObserver = nil
        }
    }

    deinit {
        stopWatching()
    }
}
