import CoreGraphics

/// Model of one workspace: the windows it holds and the order they were focused in.
struct Workspace {
    private(set) var windowIds: [CGWindowID] = []
    private var focusHistory: [CGWindowID] = []

    /// The window to focus: the most recently focused one, or any window it holds.
    var nextWindowToFocus: CGWindowID? {
        focusHistory.first ?? windowIds.first
    }

    mutating func add(_ windowId: CGWindowID) {
        windowIds.append(windowId)
    }

    /// Drops the window from the focus history too, so a window that left cannot be picked
    /// as the next focus, and cannot be revived when macOS reuses its id.
    mutating func remove(_ windowId: CGWindowID) {
        windowIds.removeAll { $0 == windowId }
        focusHistory.removeAll { $0 == windowId }
    }

    /// A window the workspace does not hold is not recorded, which keeps the history a
    /// subset of `windowIds`.
    mutating func recordFocus(on windowId: CGWindowID) {
        guard windowIds.contains(windowId) else { return }

        focusHistory = [windowId] + focusHistory.filter { $0 != windowId }
    }
}
