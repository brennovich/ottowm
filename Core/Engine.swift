import CoreGraphics
import os

// Orchestrates windows lifecycle events and hotkey commands, keeping the pure
// Workspaces and the Space in sync.
final class Engine {
    private let space: any Space
    private let window: (CGWindowID) -> (any Window)?
    private let focusedWindow: () -> (any Window)?
    private let model = Workspaces()
    private var ignoreNextManualNavigation = false

    init(
        space: any Space,
        window: @escaping (CGWindowID) -> (any Window)?,
        focusedWindow: @escaping () -> (any Window)?
    ) {
        self.space = space
        self.window = window
        self.focusedWindow = focusedWindow
    }

    var currentVirtualSpace: Int {
        model.getCurrentVirtualSpace()
    }

    var managedWindowIds: Set<CGWindowID> {
        model.allWindowIds()
    }

    func start(windows: [any Window]) {
        space.setupForMainScreen()

        for win in windows {
            assignWindowToVirtualSpace(win, 1)
        }

        space.startWatchingForManualNavigation { [weak self] placement in
            guard placement == .storage else { return }
            self?.handleManualNavigation()
        }
    }

    func handle(_ event: WindowEvent) {
        switch event {
        case let .created(win):
            assignWindowToVirtualSpace(win, model.getCurrentVirtualSpace())
        case let .focused(win):
            handleFocused(win)
        case let .destroyed(windowId):
            handleDestroyed(windowId)
        }
    }

    func switchToVirtualSpace(_ virtualSpace: Int) {
        let onManagedSpace = space.isOnManagedSpace() || model.allWindowIds().isEmpty
        Log.engine.info("switch requested target=\(virtualSpace, privacy: .public) current=\(self.model.getCurrentVirtualSpace(), privacy: .public) onManagedSpace=\(onManagedSpace, privacy: .public)")

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

    func moveWindowToVirtualSpace(_ window: (any Window)?, _ virtualSpace: Int) {
        guard virtualSpace >= 1 else {
            Log.engine.info("move dropped: invalid virtual space \(virtualSpace, privacy: .public)")
            return
        }
        guard let win = window ?? focusedWindow(), isValidWindow(win) else {
            Log.engine.info("move to \(virtualSpace, privacy: .public) dropped: no valid window to move")
            return
        }

        let placement: Placement = virtualSpace == model.getCurrentVirtualSpace() ? .active : .storage
        Log.engine.info("moving window id=\(win.id, privacy: .public) app=\(win.appName, privacy: .public) to space \(virtualSpace, privacy: .public) placement=\(String(describing: placement), privacy: .public)")
        space.moveWindowToSpace(win.id, placement)
        model.moveWindowToVirtualSpace(win.id, virtualSpace)

        restoreWindowsFocusForVirtualSpace()
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
        Log.engine.debug("destroyed id=\(windowId, privacy: .public) hadTabSiblings=\(hasTabSiblings, privacy: .public)")
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
        Log.engine.info("manual navigation → space \(target, privacy: .public) window id=\(win.id, privacy: .public)")
        switchSpaces(target)
    }

    private func switchSpaces(_ virtualSpace: Int) {
        if let focused = focusedWindow(), isValidWindow(focused) {
            model.saveFocusedWindowInVirtualSpace(model.getCurrentVirtualSpace(), focused.id)
        }

        let categorized = model.categorizeWindowsForTransition(virtualSpace)
        Log.engine.info("switching to \(virtualSpace, privacy: .public) toActive=\(String(describing: categorized.toActive), privacy: .public) toStorage=\(String(describing: categorized.toStorage), privacy: .public)")
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
        let currentSpace = model.getCurrentVirtualSpace()

        if let osFocused = focusedWindow(), isValidWindow(osFocused),
           model.getVirtualSpaceForWindow(osFocused.id) == currentSpace {
            model.saveFocusedWindowInVirtualSpace(currentSpace, osFocused.id)
            Log.engine.debug("focus kept id=\(osFocused.id, privacy: .public) space=\(currentSpace, privacy: .public)")
            return true
        }

        if let windowId = model.prepareWindowToBeFocusedOnCurrentVirtualSpace(),
           let win = window(windowId) {
            Log.engine.debug("focus restored id=\(windowId, privacy: .public) space=\(currentSpace, privacy: .public)")
            win.focus()
            return true
        }

        Log.engine.debug("no window to focus in space \(currentSpace, privacy: .public)")
        return false
    }

    private func isValidWindow(_ win: any Window) -> Bool {
        if win.id == 0 {
            Log.engine.debug("invalid window app=\(win.appName, privacy: .public): id is 0")
            return false
        }
        if !win.isStandard {
            Log.engine.debug("invalid window id=\(win.id, privacy: .public) app=\(win.appName, privacy: .public): not standard")
            return false
        }
        if win.isFullScreen {
            Log.engine.debug("invalid window id=\(win.id, privacy: .public) app=\(win.appName, privacy: .public): full screen")
            return false
        }
        if !space.managesWindow(win.id) {
            Log.engine.debug("invalid window id=\(win.id, privacy: .public) app=\(win.appName, privacy: .public): not managed by space")
            return false
        }
        return true
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
