import AppKit
import CoreGraphics

// Emulates the active/storage native-Space distinction on a single real macOS
// Space: storage windows are pushed into the bottom-right corner nub and restored
// to their captured frame on switch. Ported from VirtualSpace.lua, replacing all
// hs.spaces (private CGS) usage with public APIs injected as seams.
final class VirtualSpace: Space {
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

    func isOnManagedSpace() -> Bool {
        !onScreenWindowIds().isDisjoint(with: managedWindowIds())
    }

    func activateManagedSpace() {
        for windowId in managedWindowIds() {
            if let win = window(windowId) {
                Log.space.debug("activating managed space via id=\(windowId)")
                win.focus()
                return
            }
        }
        Log.space.debug("activateManagedSpace: no live managed window")
    }

    func managesWindow(_ windowId: CGWindowID) -> Bool {
        onScreenWindowIds().contains(windowId)
    }

    func moveWindowToSpace(_ windowId: CGWindowID, _ space: Placement) {
        Telemetry.shared.span("moveWindowToSpace(\(windowId))") {
            switch space {
            case .storage:
                if hiddenWindowFrames[windowId] != nil { return }
                guard let (win, originalFrame) = movableWindow(windowId, space) else { return }
                let hidden = hiddenFrame(for: originalFrame, on: screen)
                hiddenWindowFrames[windowId] = originalFrame
                win.setFrame(hidden)
                Log.space.debug("hid id=\(windowId) from=\(originalFrame) to=\(hidden)")
            case .active:
                guard let originalFrame = hiddenWindowFrames[windowId] else {
                    Log.space.info("cannot restore id=\(windowId): no saved frame")
                    return
                }
                guard let (win, _) = movableWindow(windowId, space) else { return }
                win.setFrame(originalFrame)
                hiddenWindowFrames[windowId] = nil
                Log.space.debug("restored id=\(windowId) to=\(originalFrame)")
            }
        }
    }

    private func movableWindow(_ windowId: CGWindowID, _ space: Placement) -> (window: any Window, frame: CGRect)? {
        guard let win = window(windowId), let frame = win.movableFrame() else {
            Log.space.info("cannot move id=\(windowId) to \(space): window not found or not movable")
            return nil
        }
        return (win, frame)
    }

    func windowSpaces(_ windowId: CGWindowID) -> Placement {
        hiddenWindowFrames[windowId] != nil ? .storage : .active
    }

    func startWatchingForManualNavigation(_ callback: @escaping (Placement) -> Void) {
        stopWatchingForManualNavigation()
        manualNavigationObserver = notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.handleActiveSpaceChange(callback)
        }
    }

    func forgetWindow(_ windowId: CGWindowID) {
        hiddenWindowFrames[windowId] = nil
    }

    private func handleActiveSpaceChange(_ callback: (Placement) -> Void) {
        guard let focusedId = focusedWindowId(), hiddenWindowFrames[focusedId] != nil else {
            Log.space.debug("native space change ignored: no hidden window focused")
            return
        }
        Log.space.info("native space change with hidden window focused id=\(focusedId)")
        callback(.storage)
    }

    private func recoverWindowsStuckAtHiddenEdge(_ windows: [WindowSnapshot]) {
        for snapshot in windows where !snapshot.isMinimized && isStuckAtHiddenEdge(snapshot.frame, on: screen) {
            Log.space.info("recovering \(snapshot.logDescription) stuck at hidden edge")
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
