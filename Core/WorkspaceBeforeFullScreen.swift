import CoreGraphics

/// Model that remembers the workspace a window returns to when it leaves full screen.
struct WorkspaceBeforeFullScreen {
    private var workspaces: [CGWindowID: Int] = [:]

    func workspace(of windowId: CGWindowID) -> Int? {
        workspaces[windowId]
    }

    mutating func record(_ windowId: CGWindowID, in workspace: Int) {
        workspaces[windowId] = workspace
    }

    /// Reads the workspace and drops the record, so the window returns to it once.
    mutating func take(_ windowId: CGWindowID) -> Int? {
        workspaces.removeValue(forKey: windowId)
    }

    mutating func forget(_ windowId: CGWindowID) {
        _ = take(windowId)
    }
}
