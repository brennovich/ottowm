import CoreGraphics

struct Workspace {
    private(set) var windowIds: [CGWindowID] = []
    private var focusHistory: [CGWindowID] = []

    var nextWindowToFocus: CGWindowID? {
        focusHistory.first ?? windowIds.first
    }

    mutating func add(_ windowId: CGWindowID) {
        windowIds.append(windowId)
    }

    mutating func remove(_ windowId: CGWindowID) {
        windowIds.removeAll { $0 == windowId }
        focusHistory.removeAll { $0 == windowId }
    }

    mutating func recordFocus(on windowId: CGWindowID) {
        guard windowIds.contains(windowId) else { return }

        focusHistory = [windowId] + focusHistory.filter { $0 != windowId }
    }
}
