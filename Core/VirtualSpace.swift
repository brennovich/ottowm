import AppKit
import CoreGraphics

// Emulates the active/storage native-Space distinction on a single real macOS
// Space: storage windows are pushed into the bottom-right corner nub and restored
// to their captured frame on switch. Ported from VirtualSpace.lua, replacing all
// hs.spaces (private CGS) usage with public APIs injected as seams.
final class VirtualSpace: Space {
    private let screen: Screen
    private let window: (CGWindowID) -> (any Window)?
    private let allWindows: () -> [any Window]
    private let onScreenWindowIds: () -> Set<CGWindowID>
    private let managedWindowIds: () -> Set<CGWindowID>
    private let focusedWindow: () -> (any Window)?
    private let notificationCenter: NotificationCenter

    private var hiddenWindowFrames: [CGWindowID: CGRect] = [:]
    private var manualNavigationObserver: (any NSObjectProtocol)?

    init(
        screen: Screen,
        window: @escaping (CGWindowID) -> (any Window)?,
        allWindows: @escaping () -> [any Window],
        onScreenWindowIds: @escaping () -> Set<CGWindowID>,
        managedWindowIds: @escaping () -> Set<CGWindowID>,
        focusedWindow: @escaping () -> (any Window)?,
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.screen = screen
        self.window = window
        self.allWindows = allWindows
        self.onScreenWindowIds = onScreenWindowIds
        self.managedWindowIds = managedWindowIds
        self.focusedWindow = focusedWindow
        self.notificationCenter = notificationCenter
    }

    func setupForMainScreen() {
        Telemetry.shared.span("setupForMainScreen") {
            recoverWindowsStuckAtHiddenEdge()
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
                guard let win = liveWindow(windowId, space) else { return }
                let originalFrame = win.frame
                let hidden = hiddenFrame(for: originalFrame, on: screen)
                hiddenWindowFrames[windowId] = originalFrame
                win.frame = hidden
                Log.space.debug("hid \(win.logDescription) from=\(originalFrame) to=\(hidden)")
            case .active:
                guard let originalFrame = hiddenWindowFrames[windowId] else {
                    Log.space.info("cannot restore id=\(windowId): no saved frame")
                    return
                }
                guard let win = liveWindow(windowId, space) else { return }
                win.frame = originalFrame
                hiddenWindowFrames[windowId] = nil
                Log.space.debug("restored \(win.logDescription) to=\(originalFrame)")
            }
        }
    }

    private func liveWindow(_ windowId: CGWindowID, _ space: Placement) -> (any Window)? {
        guard let win = window(windowId), !win.isMinimized else {
            Log.space.info("cannot move id=\(windowId) to \(space): window not found or minimized")
            return nil
        }
        return win
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
        guard let focused = focusedWindow(), hiddenWindowFrames[focused.id] != nil else {
            Log.space.debug("native space change ignored: no hidden window focused")
            return
        }
        Log.space.info("native space change with hidden window focused id=\(focused.id)")
        callback(.storage)
    }

    private func recoverWindowsStuckAtHiddenEdge() {
        for win in allWindows() where !win.isMinimized && isStuckAtHiddenEdge(win.frame, on: screen) {
            Log.space.info("recovering \(win.logDescription) stuck at hidden edge")
            win.frame = recoveredFrame(for: win.frame, visibleFrame: screen.visibleFrame)
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
