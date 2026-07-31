import CoreGraphics

// Orchestrates windows lifecycle events and hotkey commands, keeping the pure
// Workspaces and the Space in sync.
final class Engine {
    private let space: any Space
    private let window: (CGWindowID) -> (any Window)?
    private let focusedWindow: () -> (any Window)?
    private let onScreenWindows: OnScreenWindows
    private let model = Workspaces()
    private var ignoreNextManualNavigation = false

    init(
        space: any Space,
        window: @escaping (CGWindowID) -> (any Window)?,
        focusedWindow: @escaping () -> (any Window)?,
        onScreenWindows: OnScreenWindows
    ) {
        self.space = space
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

    func start(windows: [any Window]) {
        operation("start") {
            space.setupForMainScreen(windows: windows)

            for win in windows {
                assignWindowToVirtualSpace(win, 1)
            }

            space.startWatchingForManualNavigation { [weak self] placement in
                guard placement == .storage else { return }
                self?.handleManualNavigation()
            }
        }
    }

    func handle(_ event: WindowEvent) {
        onScreenWindows.duringOperation {
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
            let onManagedSpace = space.isOnManagedSpace() || model.allWindowIds().isEmpty
            Log.engine.info("switch requested target=\(virtualSpace) current=\(model.getCurrentVirtualSpace()) onManagedSpace=\(onManagedSpace)")

            if virtualSpace == model.getCurrentVirtualSpace() {
                if !onManagedSpace {
                    returnToManagedSpace()
                }
                return
            }

            switchSpaces(virtualSpace)

            if onManagedSpace {
                restoreWindowsFocusForVirtualSpace()
            } else {
                returnToManagedSpace()
            }
        }
    }

    func moveWindowToVirtualSpace(_ window: (any Window)?, _ virtualSpace: Int) {
        operation("moveWindowToVirtualSpace(\(virtualSpace))") {
            guard virtualSpace >= 1 else {
                Log.engine.info("move dropped: invalid virtual space \(virtualSpace)")
                return
            }
            guard let win = window ?? focusedWindow(), isValidWindow(win) else {
                Log.engine.info("move to \(virtualSpace) dropped: no valid window to move")
                return
            }

            let placement: Placement = virtualSpace == model.getCurrentVirtualSpace() ? .active : .storage
            Log.engine.info("moving window \(win.logDescription) to space \(virtualSpace) placement=\(placement)")
            space.moveWindowToSpace(win.id, placement)
            model.moveWindowToVirtualSpace(win.id, virtualSpace)

            restoreWindowsFocusForVirtualSpace()
        }
    }

    private func handleFocused(_ win: any Window) {
        if space.windowSpaces(win.id) == .storage {
            handleManualNavigation(win)
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
        space.forgetWindow(windowId)

        if !hasTabSiblings {
            restoreWindowsFocusForVirtualSpace()
        }
    }

    // Focusing a hidden window means the user navigated to it behind OttoWM's back
    // (Cmd-Tab/Dock on the same native Space, or Mission Control from another one),
    // so follow them by switching to that window's virtual space.
    private func handleManualNavigation(_ win: (any Window)? = nil) {
        operation("handleManualNavigation") {
            if ignoreNextManualNavigation {
                ignoreNextManualNavigation = false
                Log.engine.debug("ignoring manual navigation (one-shot)")
                return
            }

            if currentVirtualSpaceIsClosing() { return }

            guard let win = win ?? focusedWindow() else {
                Log.engine.debug("manual navigation dropped: no focused window")
                return
            }

            let target = model.getVirtualSpaceForWindow(win.id) ?? 1
            Log.engine.info("manual navigation → space \(target) window id=\(win.id)")
            switchSpaces(target)
        }
    }

    private func switchSpaces(_ virtualSpace: Int) {
        if let focused = focusedWindow(), isValidWindow(focused) {
            model.saveFocusedWindowInVirtualSpace(model.getCurrentVirtualSpace(), focused.id)
        }

        let categorized = model.categorizeWindowsForTransition(virtualSpace)
        Log.engine.info("switching to \(virtualSpace) toActive=\(categorized.toActive) toStorage=\(categorized.toStorage)")
        for windowId in categorized.toActive {
            space.moveWindowToSpace(windowId, .active)
        }
        for windowId in categorized.toStorage {
            space.moveWindowToSpace(windowId, .storage)
        }

        model.setCurrentVirtualSpace(virtualSpace)
    }

    private func assignWindowToVirtualSpace(_ win: any Window, _ virtualSpace: Int) {
        guard isValidWindow(win) else { return }
        model.assignWindowToSpace(win, virtualSpace)
        Log.engine.info("assigned \(win.logDescription) → space \(virtualSpace)")
    }

    private func returnToManagedSpace() {
        if !restoreWindowsFocusForVirtualSpace() {
            ignoreNextManualNavigation = true
            Log.engine.debug("returning to managed space, ignoring next manual navigation")
            space.activateManagedSpace()
        }
    }

    @discardableResult
    private func restoreWindowsFocusForVirtualSpace() -> Bool {
        operation("restoreWindowsFocus") {
            let currentSpace = model.getCurrentVirtualSpace()

            if let osFocused = focusedWindow(), isValidWindow(osFocused),
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

    // An operation is the unit both telemetry and the window-list snapshot are scoped
    // to: `isValidWindow` asks which windows are on screen several times per operation,
    // and each ask would otherwise be its own CGWindowList round trip.
    private func operation<T>(_ name: String, _ body: () -> T) -> T {
        onScreenWindows.duringOperation { Telemetry.shared.span(name, body) }
    }

    private func isValidWindow(_ win: any Window) -> Bool {
        win.id != 0 && win.isStandard && !win.isFullScreen && space.managesWindow(win.id)
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
