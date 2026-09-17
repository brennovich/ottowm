import CoreGraphics

struct Workspace: Codable, Equatable {
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

    func keeping(_ windowIds: Set<CGWindowID>) -> Workspace {
        Workspace(windowIds: self.windowIds.filter(windowIds.contains), focusHistory: focusHistory.filter(windowIds.contains))
    }

    mutating func recordFocus(on windowId: CGWindowID) {
        guard windowIds.contains(windowId) else { return }

        focusHistory = [windowId] + focusHistory.filter { $0 != windowId }
    }
}
