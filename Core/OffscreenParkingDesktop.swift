import AppKit
import CoreGraphics

// Inspired by Aerospace.app realizes Placement on a single real macOS Space: storage
// windows are parked in the bottom-right corner nub and restored to their captured
// frame on switch.
final class OffscreenParkingDesktop: Desktop {
    // The bottom-right sliver a parked window is squeezed into. macOS clamps a
    // window from leaving all screens: horizontally to a 1px sliver, vertically
    // keeping ~38px of title bar.
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

    // Returns the windows as they now stand: a recovered one no longer sits where its
    // caller saw it, and the model has to record where it ended up.
    func recover(windows: [WindowSnapshot]) -> [WindowSnapshot] {
        Telemetry.shared.span("recover") {
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
    }

    @discardableResult
    func place(_ windowId: CGWindowID, _ placement: Placement) -> Bool {
        Telemetry.shared.span("place(\(windowId))") {
            switch placement {
            case .storage:
                if hiddenWindowFrames[windowId] != nil { return reaches(windowId) }
                guard let (win, originalFrame) = movableWindow(windowId, placement) else {
                    return reaches(windowId)
                }
                let hidden = hiddenEdge.frame(parking: originalFrame)
                hiddenWindowFrames[windowId] = originalFrame
                move(win, from: originalFrame, to: hidden)
                Log.desktop.debug("hid id=\(windowId) from=\(originalFrame) to=\(hidden)")
            case .active:
                guard let originalFrame = hiddenWindowFrames[windowId] else {
                    Log.desktop.info("cannot restore id=\(windowId): no saved frame")
                    return reaches(windowId)
                }
                guard let (win, parkedFrame) = movableWindow(windowId, placement) else {
                    return reaches(windowId)
                }
                move(win, from: parkedFrame, to: originalFrame)
                hiddenWindowFrames[windowId] = nil
                Log.desktop.debug("restored id=\(windowId) to=\(originalFrame)")
            }
            return true
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

    func startWatchingForManualNavigation(_ callback: @escaping (CGWindowID) -> Void) {
        stopWatchingForManualNavigation()
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

    private func move(_ win: any Window, from current: CGRect, to target: CGRect) {
        if current.origin != target.origin { win.setPosition(target.origin) }
        if current.size != target.size { win.setSize(target.size) }
    }

    // Whether the window still exists at all. One that is merely out of reach —
    // minimized, or mid-relaunch — does and comes back; one nothing can resolve any
    // more never will, and its owner has to hear about it: an application quitting
    // evicts its windows without a destroyed notification for each of them, and the
    // model would otherwise place a corpse on every switch forever.
    private func reaches(_ windowId: CGWindowID) -> Bool {
        window(windowId) != nil
    }

    private func movableWindow(_ windowId: CGWindowID, _ placement: Placement) -> (window: any Window, frame: CGRect)? {
        guard let win = window(windowId), let frame = win.movableFrame() else {
            Log.desktop.info("cannot move id=\(windowId) to \(placement): window not found or not movable")
            return nil
        }
        return (win, frame)
    }

    private func handleActiveSpaceChange(_ callback: (CGWindowID) -> Void) {
        guard let focusedId = focusedWindowId(), hiddenWindowFrames[focusedId] != nil else {
            Log.desktop.debug("native space change: no hidden window focused")
            // macOS brings a non-fullscreen window counter part to be visible
            // when we exit its fullscreen instance. For example, a Safari video
            // in fullscreen.
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

    private func stopWatchingForManualNavigation() {
        if let manualNavigationObserver {
            notificationCenter.removeObserver(manualNavigationObserver)
            self.manualNavigationObserver = nil
        }
    }

    deinit {
        stopWatchingForManualNavigation()
    }
}
