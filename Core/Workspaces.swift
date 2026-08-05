import CoreGraphics

// Tracks windows in their respective workspace.
final class Workspaces {
    private(set) var currentWorkspace = 1

    private var focusedWindows: [Int: [CGWindowID]] = [:]
    private var windowWorkspaceMap: [CGWindowID: Int] = [:]
    private var workspaceWindowsMap: [Int: [CGWindowID]] = [:]

    private var tabGroups = TabGroups()

    var allWindowIds: Set<CGWindowID> {
        Set(windowWorkspaceMap.keys)
    }

    func saveFocusedWindowInWorkspace(_ workspace: Int, _ windowId: CGWindowID) {
        focusedWindows[workspace] = [windowId] + (focusedWindows[workspace] ?? []).filter { $0 != windowId }
    }

    func workspace(for windowId: CGWindowID) -> Int? {
        windowWorkspaceMap[windowId]
    }

    func windowIds(in workspace: Int) -> [CGWindowID] {
        workspaceWindowsMap[workspace] ?? []
    }

    // A tab group is one unit and it already sits somewhere: a window joining one lands
    // where the group is, rather than dragging the whole group to the workspace it was
    // discovered from. Returns the workspace the window actually landed in.
    @discardableResult
    func assignWindowToWorkspace(_ window: WindowSnapshot, _ workspace: Int, tabCount: Int = 1) -> Int {
        tabGroups.add(window, tabCount: tabCount)
        let target = workspaceOfTabGroup(window.id) ?? workspace
        assignTabGroup(of: window.id, to: target)
        saveFocusedWindowInWorkspace(target, window.id)
        return target
    }

    func moveWindowToWorkspace(_ windowId: CGWindowID, _ workspace: Int) {
        assignTabGroup(of: windowId, to: workspace)
        saveFocusedWindowInWorkspace(workspace, windowId)
    }

    // Returns whether a surviving tab sibling took over the focus, so there is
    // nothing left to restore.
    @discardableResult
    func unregisterWindowById(_ windowId: CGWindowID) -> Bool {
        var focusSettled = false
        if let firstTabSibling = tabGroups.siblings(of: windowId).first,
           let siblingWorkspace = windowWorkspaceMap[firstTabSibling] {
            saveFocusedWindowInWorkspace(siblingWorkspace, firstTabSibling)
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
            saveFocusedWindowInWorkspace(currentWorkspace, windowId)
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

    func nextWindowToFocus() -> CGWindowID? {
        return focusedWindows[currentWorkspace]?.first { windowWorkspaceMap[$0] == currentWorkspace }
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
