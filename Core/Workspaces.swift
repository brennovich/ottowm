import CoreGraphics

/// Tracks windows in their respective workspace.
final class Workspaces {
    private(set) var currentWorkspace = 1

    private var focusedWindows: [Int: [CGWindowID]] = [:]
    private var windowWorkspaceMap: [CGWindowID: Int] = [:]
    private var workspaceWindowsMap: [Int: [CGWindowID]] = [:]

    private var tabGroups = TabGroups()

    var allWindowIds: Set<CGWindowID> {
        Set(windowWorkspaceMap.keys)
    }

    func recordFocus(on windowId: CGWindowID, in workspace: Int) {
        focusedWindows[workspace] = [windowId] + (focusedWindows[workspace] ?? []).filter { $0 != windowId }
    }

    func workspace(for windowId: CGWindowID) -> Int? {
        windowWorkspaceMap[windowId]
    }

    func windowIds(in workspace: Int) -> [CGWindowID] {
        workspaceWindowsMap[workspace] ?? []
    }

    /// Assigns the window to `workspace`, or to the workspace its tab group already sits in.
    ///
    /// A tab group is one unit, so a window joining one lands where the group is rather
    /// than dragging the group to the workspace it was discovered from.
    /// - Returns: the workspace the window landed in.
    @discardableResult
    func assign(_ window: WindowSnapshot, to workspace: Int, tabCount: Int = 1) -> Int {
        tabGroups.add(window, tabCount: tabCount)
        let target = workspaceOfTabGroup(window.id) ?? workspace
        assignTabGroup(of: window.id, to: target)
        recordFocus(on: window.id, in: target)
        return target
    }

    func move(_ windowId: CGWindowID, to workspace: Int) {
        assignTabGroup(of: windowId, to: workspace)
        recordFocus(on: windowId, in: workspace)
    }

    /// The windows macOS takes out of reach together with this one: a tab group is a single
    /// window to it, so its tabs are minimized, restored and moved as one.
    func tabGroupMembers(of windowId: CGWindowID) -> [CGWindowID] {
        tabGroups.members(of: windowId)
    }

    /// Drops the window from its workspace and from the focus history.
    /// - Returns: `true` if a surviving tab sibling took over the focus, so there is
    ///   nothing left to restore.
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
            removeWindowFromList(workspace, windowId)
        }
        removeWindowFromFocusHistory(windowId)
        return focusSettled
    }

    func switchTo(_ targetWorkspace: Int, leavingFocusOn windowId: CGWindowID?) -> (toActive: [CGWindowID], toStorage: [CGWindowID]) {
        let placement = (toActive: [CGWindowID](), toStorage: [CGWindowID]())
        guard targetWorkspace != currentWorkspace else { return placement }

        if let windowId {
            recordFocus(on: windowId, in: currentWorkspace)
        }
        currentWorkspace = targetWorkspace

        return windowWorkspaceMap.reduce(into: placement) { p, e in
            if e.value == targetWorkspace {
                p.toActive.append(e.key)
            } else {
                p.toStorage.append(e.key)
            }
        }
    }

    /// The window the current workspace should focus: the most recently focused one
    /// still in it, or any window it holds.
    /// - Complexity: O(*n*) in the number of windows of the current workspace.
    var nextWindowToFocus: CGWindowID? {
        focusedWindows[currentWorkspace]?.first { windowWorkspaceMap[$0] == currentWorkspace }
            ?? workspaceWindowsMap[currentWorkspace]?.first
    }

    private func assign(_ windowId: CGWindowID, to workspace: Int) {
        if let previousWorkspace = windowWorkspaceMap[windowId] {
            guard previousWorkspace != workspace else { return }
            removeWindowFromList(previousWorkspace, windowId)
        }

        workspaceWindowsMap[workspace, default: []].append(windowId)
        windowWorkspaceMap[windowId] = workspace
    }

    private func workspaceOfTabGroup(_ windowId: CGWindowID) -> Int? {
        tabGroups.siblings(of: windowId).lazy.compactMap { self.windowWorkspaceMap[$0] }.first
    }

    private func assignTabGroup(of windowId: CGWindowID, to workspace: Int) {
        for memberId in tabGroups.members(of: windowId) {
            assign(memberId, to: workspace)
        }
    }

    private func removeWindowFromList(_ workspace: Int, _ windowId: CGWindowID) {
        workspaceWindowsMap[workspace]?.removeAll { $0 == windowId }
    }

    private func removeWindowFromFocusHistory(_ windowId: CGWindowID) {
        focusedWindows = focusedWindows.mapValues { $0.filter { $0 != windowId } }
    }
}
