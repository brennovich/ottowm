import CoreGraphics

// Orchestrates windows lifecycle events and hotkey commands, keeping the pure
// Workspaces model and the physical Desktop in sync.
final class Engine {
    private let desktop: any Desktop
    private let window: (CGWindowID) -> (any Window)?
    private let focusedWindow: OperationCache<WindowSnapshot?>
    private let onScreenWindows: OperationCache<Set<CGWindowID>>
    private let model = Workspaces()
    private var ignoreNextManualNavigation = false

    init(
        desktop: any Desktop,
        window: @escaping (CGWindowID) -> (any Window)?,
        focusedWindow: OperationCache<WindowSnapshot?>,
        onScreenWindows: OperationCache<Set<CGWindowID>>
    ) {
        self.desktop = desktop
        self.window = window
        self.focusedWindow = focusedWindow
        self.onScreenWindows = onScreenWindows
    }

    var currentVirtualSpace: Int {
        model.getCurrentVirtualSpace()
    }

    var managedWindowIds: Set<CGWindowID> {
        model.allWindowIds()
    }

    func start(windows: [WindowSnapshot]) {
        operation("start") {
            desktop.setupForMainScreen(windows: windows)

            for win in windows {
                assignWindowToVirtualSpace(win, 1)
            }

            desktop.startWatchingForManualNavigation { [weak self] windowId in
                self?.handleManualNavigation(windowId)
            }
        }
    }

    func handle(_ event: WindowEvent) {
        duringOperation {
            switch event {
            case let .created(win):
                assignWindowToVirtualSpace(win, model.getCurrentVirtualSpace())
            case let .focused(win):
                handleFocused(win)
            case let .destroyed(windowId):
                handleDestroyed(windowId)
            }
        }
    }

    func switchToVirtualSpace(_ virtualSpace: Int) {
        operation("switchToVirtualSpace(\(virtualSpace))") {
            let onDesktop = desktop.isFrontmost() || model.allWindowIds().isEmpty
            Log.engine.info("switch requested target=\(virtualSpace) current=\(self.model.getCurrentVirtualSpace()) onDesktop=\(onDesktop)")

            if virtualSpace == model.getCurrentVirtualSpace() {
                if !onDesktop {
                    returnToDesktop()
                }
                return
            }

            switchSpaces(virtualSpace)

            if onDesktop {
                restoreWindowsFocusForVirtualSpace()
            } else {
                returnToDesktop()
            }
        }
    }

    func moveWindowToVirtualSpace(_ window: WindowSnapshot?, _ virtualSpace: Int) {
        operation("moveWindowToVirtualSpace(\(virtualSpace))") {
            guard virtualSpace >= 1 else {
                Log.engine.info("move dropped: invalid virtual space \(virtualSpace)")
                return
            }
            guard let win = window ?? focusedWindow.value(), isValidWindow(win) else {
                Log.engine.info("move to \(virtualSpace) dropped: no valid window to move")
                return
            }

            let placement: Placement = virtualSpace == model.getCurrentVirtualSpace() ? .active : .storage
            Log.engine.info("moving window \(win.logDescription) to space \(virtualSpace) placement=\(placement)")
            desktop.place(win.id, placement)
            model.moveWindowToVirtualSpace(win.id, virtualSpace)

            restoreWindowsFocusForVirtualSpace()
        }
    }

    private func handleFocused(_ win: WindowSnapshot) {
        if desktop.placement(of: win.id) == .storage {
            // Focus notifications are delivered asynchronously, so this one may
            // describe a focus OttoWM itself caused before the switch that hid the
            // window. Acting on such an echo bounces straight back to the space we
            // just left. Only the window the OS considers focused right now counts.
            guard focusedWindow.value()?.id == win.id else {
                Log.engine.debug("ignoring stale focus event id=\(win.id)")
                return
            }
            handleManualNavigation(win.id)
            return
        }

        guard isValidWindow(win) else { return }

        if let virtualSpace = model.getVirtualSpaceForWindow(win.id) {
            model.saveFocusedWindowInVirtualSpace(virtualSpace, win.id)
        } else {
            assignWindowToVirtualSpace(win, model.getCurrentVirtualSpace())
        }
    }

    private func handleDestroyed(_ windowId: CGWindowID) {
        let hasTabSiblings = model.getTabSiblingsBeforeDestruction(windowId) != nil
        Log.engine.debug("destroyed id=\(windowId) hadTabSiblings=\(hasTabSiblings)")
        model.unregisterWindowById(windowId)
        desktop.forget(windowId)

        if !hasTabSiblings {
            restoreWindowsFocusForVirtualSpace()
        }
    }

    // Focusing a hidden window means the user navigated to it behind OttoWM's back
    // (Cmd-Tab/Dock on the same native Space, or Mission Control from another one),
    // so follow them by switching to that window's virtual space.
    private func handleManualNavigation(_ windowId: CGWindowID) {
        operation("handleManualNavigation") {
            if ignoreNextManualNavigation {
                ignoreNextManualNavigation = false
                Log.engine.debug("ignoring manual navigation (one-shot)")
                return
            }

            if currentVirtualSpaceIsClosing() { return }

            let target = model.getVirtualSpaceForWindow(windowId) ?? 1
            Log.engine.info("manual navigation → space \(target) window id=\(windowId)")
            switchSpaces(target)
        }
    }

    private func switchSpaces(_ virtualSpace: Int) {
        if let focused = focusedWindow.value(), isValidWindow(focused) {
            model.saveFocusedWindowInVirtualSpace(model.getCurrentVirtualSpace(), focused.id)
        }

        let categorized = model.categorizeWindowsForTransition(virtualSpace)
        Log.engine.info("switching to \(virtualSpace) toActive=\(categorized.toActive) toStorage=\(categorized.toStorage)")
        for windowId in categorized.toActive {
            desktop.place(windowId, .active)
        }
        for windowId in categorized.toStorage {
            desktop.place(windowId, .storage)
        }

        model.setCurrentVirtualSpace(virtualSpace)
    }

    private func assignWindowToVirtualSpace(_ win: WindowSnapshot, _ virtualSpace: Int) {
        guard isValidWindow(win) else { return }
        model.assignWindowToSpace(win, virtualSpace)
        Log.engine.info("assigned \(win.logDescription) → space \(virtualSpace)")
    }

    private func returnToDesktop() {
        if !restoreWindowsFocusForVirtualSpace() {
            ignoreNextManualNavigation = true
            Log.engine.debug("returning to desktop, ignoring next manual navigation")
            desktop.bringToFront()
        }
    }

    @discardableResult
    private func restoreWindowsFocusForVirtualSpace() -> Bool {
        operation("restoreWindowsFocus") {
            let currentSpace = model.getCurrentVirtualSpace()

            if let osFocused = focusedWindow.value(), isValidWindow(osFocused),
               model.getVirtualSpaceForWindow(osFocused.id) == currentSpace {
                model.saveFocusedWindowInVirtualSpace(currentSpace, osFocused.id)
                return true
            }

            if let windowId = model.prepareWindowToBeFocusedOnCurrentVirtualSpace(),
               let win = window(windowId) {
                win.focus()
                return true
            }

            Log.engine.debug("no window to focus in space \(currentSpace)")
            return false
        }
    }

    // An operation is the unit telemetry and both IPC-backed reads are scoped to:
    // `isValidWindow` asks which windows are on screen several times per operation and
    // the focused window is read more than once, and each ask would otherwise be its
    // own round trip.
    private func operation<T>(_ name: String, _ body: () -> T) -> T {
        duringOperation { Telemetry.shared.span(name, body) }
    }

    private func duringOperation<T>(_ body: () -> T) -> T {
        onScreenWindows.duringOperation { focusedWindow.duringOperation(body) }
    }

    private func isValidWindow(_ win: WindowSnapshot) -> Bool {
        win.id != 0 && win.isStandard && !win.isFullScreen && desktop.contains(win.id)
    }

    // True while the current virtual space's windows are all mid-destruction: the
    // model still lists them but none resolve to a live window anymore. Focus events
    // fired during that teardown must not be mistaken for manual navigation.
    private func currentVirtualSpaceIsClosing() -> Bool {
        let windowIds = model.getWindowsInVirtualSpace(model.getCurrentVirtualSpace())
        if windowIds.isEmpty { return false }

        return windowIds.allSatisfy { window($0) == nil }
    }
}
