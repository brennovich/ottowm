import CoreGraphics

/// Model that maps windows to their respective workspace, keeping the focus history of
/// each workspace and the active workspace.
final class Workspaces {
    private(set) var current = 1

    private var workspaces: [Int: Workspace] = [:]
    private var windowWorkspaceMap: [CGWindowID: Int] = [:]

    private var tabGroups = TabGroups()

    var allWindowIds: Set<CGWindowID> {
        Set(windowWorkspaceMap.keys)
    }

    func recordFocus(on windowId: CGWindowID, in workspace: Int) {
        workspaces[workspace]?.recordFocus(on: windowId)
    }

    func workspace(for windowId: CGWindowID) -> Int? {
        windowWorkspaceMap[windowId]
    }

    func windowIds(in workspace: Int) -> [CGWindowID] {
        workspaces[workspace]?.windowIds ?? []
    }

    /// Assigns the window to `workspace`, or to the workspace its tab group already sits in.
    ///
    /// A tab group moves as one unit. A window joining a group lands where the group is;
    /// the group does not follow the window.
    /// - Returns: the workspace the window landed in.
    @discardableResult
    func assign(_ window: WindowSnapshot, to workspace: Int, tabCount: Int = 1) -> Int {
        tabGroups.add(window, tabCount: tabCount)
        let target = tabGroups.siblings(of: window.id).lazy.compactMap { self.windowWorkspaceMap[$0] }.first ?? workspace
        assignTabGroup(of: window.id, to: target)
        recordFocus(on: window.id, in: target)
        return target
    }

    func move(_ windowId: CGWindowID, to workspace: Int) {
        assignTabGroup(of: windowId, to: workspace)
        recordFocus(on: windowId, in: workspace)
    }

    /// The windows macOS minimizes, restores and moves together with this one. A tab group
    /// is one window to macOS.
    func tabGroupMembers(of windowId: CGWindowID) -> [CGWindowID] {
        tabGroups.members(of: windowId)
    }

    /// Drops the window from its workspace and from the focus history.
    /// - Returns: `true` if a surviving tab sibling took the focus, so no other window
    ///   needs it.
    @discardableResult
    func remove(_ windowId: CGWindowID) -> Bool {
        var focusSettled = false
        if let firstTabSibling = tabGroups.siblings(of: windowId).first,
           let siblingWorkspace = windowWorkspaceMap[firstTabSibling] {
            recordFocus(on: firstTabSibling, in: siblingWorkspace)
            focusSettled = true
        }
        tabGroups.remove(windowId)

        if let workspace = windowWorkspaceMap.removeValue(forKey: windowId) {
            workspaces[workspace]?.remove(windowId)
        }
        return focusSettled
    }

    func switchTo(_ targetWorkspace: Int, leavingFocusOn windowId: CGWindowID?) -> (toActive: [CGWindowID], toStorage: [CGWindowID]) {
        let placement = (toActive: [CGWindowID](), toStorage: [CGWindowID]())
        guard targetWorkspace != current else { return placement }

        if let windowId {
            recordFocus(on: windowId, in: current)
        }
        current = targetWorkspace

        return windowWorkspaceMap.reduce(into: placement) { p, e in
            if e.value == targetWorkspace {
                p.toActive.append(e.key)
            } else {
                p.toStorage.append(e.key)
            }
        }
    }

    /// The window to focus in the current workspace.
    var nextWindowToFocus: CGWindowID? {
        workspaces[current]?.nextWindowToFocus
    }

    private func assignTabGroup(of windowId: CGWindowID, to workspace: Int) {
        for memberId in tabGroups.members(of: windowId) {
            if let previousWorkspace = windowWorkspaceMap[memberId] {
                guard previousWorkspace != workspace else { continue }
                workspaces[previousWorkspace]?.remove(memberId)
            }

            workspaces[workspace, default: Workspace()].add(memberId)
            windowWorkspaceMap[memberId] = workspace
        }
    }
}
