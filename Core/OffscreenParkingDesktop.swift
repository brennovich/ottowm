import AppKit
import CoreGraphics

// Inspired by Aerospace.app realizes Placement on a single real macOS Space: storage
// windows are parked in the bottom-right corner nub and restored to their captured
// frame on switch.
final class OffscreenParkingDesktop: Desktop {
    // The bottom-right sliver a parked window is squeezed into. macOS clamps a
    // window from leaving all screens: horizontally to a 1px sliver, vertically
    // keeping ~38px of title bar. Pinning both axes to the corner confines the
    // leftover to a tiny ~1x38px nub.
    struct HiddenEdge {
        private static let epsilon: CGFloat = 1
        private static let detectionMargin: CGFloat = 10

        let screen: Screen

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
        screen: Screen,
        window: @escaping (CGWindowID) -> (any Window)?,
        focusedWindowId: @escaping () -> CGWindowID?,
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        hiddenEdge = HiddenEdge(screen: screen)
        self.window = window
        self.focusedWindowId = focusedWindowId
        self.notificationCenter = notificationCenter
    }

    func recover(windows: [WindowSnapshot]) {
        Telemetry.shared.span("recover") {
            recoverWindowsStuckAtHiddenEdge(windows)
        }
    }

    func place(_ windowId: CGWindowID, _ placement: Placement) {
        Telemetry.shared.span("place(\(windowId))") {
            switch placement {
            case .storage:
                if hiddenWindowFrames[windowId] != nil { return }
                guard let (win, originalFrame) = movableWindow(windowId, placement) else { return }
                let hidden = hiddenEdge.frame(parking: originalFrame)
                hiddenWindowFrames[windowId] = originalFrame
                win.setFrame(hidden)
                Log.desktop.debug("hid id=\(windowId) from=\(originalFrame) to=\(hidden)")
            case .active:
                guard let originalFrame = hiddenWindowFrames[windowId] else {
                    Log.desktop.info("cannot restore id=\(windowId): no saved frame")
                    return
                }
                guard let (win, _) = movableWindow(windowId, placement) else { return }
                win.setFrame(originalFrame)
                hiddenWindowFrames[windowId] = nil
                Log.desktop.debug("restored id=\(windowId) to=\(originalFrame)")
            }
        }
    }

    private func movableWindow(_ windowId: CGWindowID, _ placement: Placement) -> (window: any Window, frame: CGRect)? {
        guard let win = window(windowId), let frame = win.movableFrame() else {
            Log.desktop.info("cannot move id=\(windowId) to \(placement): window not found or not movable")
            return nil
        }
        return (win, frame)
    }

    func placement(of windowId: CGWindowID) -> Placement {
        hiddenWindowFrames[windowId] != nil ? .storage : .active
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

    private func handleActiveSpaceChange(_ callback: (CGWindowID) -> Void) {
        guard let focusedId = focusedWindowId(), hiddenWindowFrames[focusedId] != nil else {
            Log.desktop.debug("native space change: no hidden window focused")
            parkWindowsPulledBackOnScreen()
            return
        }
        Log.desktop.info("native space change with hidden window focused id=\(focusedId)")
        callback(focusedId)
    }

    // macOS constrains a window to be fully on screen when the space it sits on
    // becomes active again, undoing a park issued while that space was in the
    // background.
    private func parkWindowsPulledBackOnScreen() {
        for (windowId, originalFrame) in hiddenWindowFrames {
            guard let win = window(windowId),
                  let frame = win.movableFrame(),
                  !hiddenEdge.holds(frame)
            else { continue }

            let hidden = hiddenEdge.frame(parking: originalFrame)
            win.setFrame(hidden)
            Log.desktop.info("re-hid id=\(windowId) pulled back to \(frame), to=\(hidden)")
        }
    }

    private func recoverWindowsStuckAtHiddenEdge(_ windows: [WindowSnapshot]) {
        for snapshot in windows where !snapshot.isMinimized && hiddenEdge.holds(snapshot.frame) {
            Log.desktop.info("recovering \(snapshot.logDescription) stuck at hidden edge")
            let recovered = hiddenEdge.recovered(from: snapshot.frame)
            window(snapshot.id)?.setFrame(recovered)
        }
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
