import AppKit
import CoreGraphics

// Realizes Placement on a single real macOS Space: storage windows are parked
// in the bottom-right corner nub and restored to their captured frame on switch.
// Ported from VirtualSpace.lua, replacing all hs.spaces (private CGS) usage with
// public APIs injected as seams.
final class OffscreenParkingDesktop: Desktop {
    private let screen: Screen
    private let window: (CGWindowID) -> (any Window)?
    private let onScreenWindowIds: () -> Set<CGWindowID>
    private let managedWindowIds: () -> Set<CGWindowID>
    private let focusedWindowId: () -> CGWindowID?
    private let notificationCenter: NotificationCenter

    private var hiddenWindowFrames: [CGWindowID: CGRect] = [:]
    private var manualNavigationObserver: (any NSObjectProtocol)?

    init(
        screen: Screen,
        window: @escaping (CGWindowID) -> (any Window)?,
        onScreenWindowIds: @escaping () -> Set<CGWindowID>,
        managedWindowIds: @escaping () -> Set<CGWindowID>,
        focusedWindowId: @escaping () -> CGWindowID?,
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.screen = screen
        self.window = window
        self.onScreenWindowIds = onScreenWindowIds
        self.managedWindowIds = managedWindowIds
        self.focusedWindowId = focusedWindowId
        self.notificationCenter = notificationCenter
    }

    func setupForMainScreen(windows: [WindowSnapshot]) {
        Telemetry.shared.span("setupForMainScreen") {
            recoverWindowsStuckAtHiddenEdge(windows)
        }
    }

    func isFrontmost() -> Bool {
        !onScreenWindowIds().isDisjoint(with: managedWindowIds())
    }

    func bringToFront() {
        for windowId in managedWindowIds() {
            if let win = window(windowId) {
                Log.desktop.debug("bringing desktop to front via id=\(windowId)")
                win.focus()
                return
            }
        }
        Log.desktop.debug("bringToFront: no live managed window")
    }

    func contains(_ windowId: CGWindowID) -> Bool {
        onScreenWindowIds().contains(windowId)
    }

    func place(_ windowId: CGWindowID, _ placement: Placement) {
        Telemetry.shared.span("place(\(windowId))") {
            switch placement {
            case .storage:
                if hiddenWindowFrames[windowId] != nil { return }
                guard let (win, originalFrame) = movableWindow(windowId, placement) else { return }
                let hidden = hiddenFrame(for: originalFrame, on: screen)
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
    // background — which is what happens when a switch is triggered from an app's
    // full screen space. Park them again, from the frame captured the first time.
    private func parkWindowsPulledBackOnScreen() {
        for (windowId, originalFrame) in hiddenWindowFrames {
            guard let win = window(windowId),
                  let frame = win.movableFrame(),
                  !isStuckAtHiddenEdge(frame, on: screen)
            else { continue }

            let hidden = hiddenFrame(for: originalFrame, on: screen)
            win.setFrame(hidden)
            Log.desktop.info("re-hid id=\(windowId) pulled back to \(frame), to=\(hidden)")
        }
    }

    private func recoverWindowsStuckAtHiddenEdge(_ windows: [WindowSnapshot]) {
        for snapshot in windows where !snapshot.isMinimized && isStuckAtHiddenEdge(snapshot.frame, on: screen) {
            Log.desktop.info("recovering \(snapshot.logDescription) stuck at hidden edge")
            let recovered = recoveredFrame(for: snapshot.frame, visibleFrame: screen.visibleFrame)
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
