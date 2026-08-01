import CoreGraphics

// Tracks windows in their respective workspace via mappings of windows to workspaces.
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
        var focusHistory = focusedWindows[workspace] ?? []
        focusHistory.removeAll { $0 == windowId }
        focusHistory.insert(windowId, at: 0)
        focusedWindows[workspace] = focusHistory
    }

    func workspace(for windowId: CGWindowID) -> Int? {
        windowWorkspaceMap[windowId]
    }

    func windowIds(in workspace: Int) -> [CGWindowID] {
        workspaceWindowsMap[workspace] ?? []
    }

    func assignWindowToWorkspace(_ window: WindowSnapshot, _ workspace: Int) {
        tabGroups.add(window)
        assignTabGroup(of: window.id, to: workspace)
        saveFocusedWindowInWorkspace(workspace, window.id)
    }

    func moveWindowToWorkspace(_ windowId: CGWindowID, _ workspace: Int) {
        assignTabGroup(of: windowId, to: workspace)
        saveFocusedWindowInWorkspace(workspace, windowId)
    }

    func unregisterWindowById(_ windowId: CGWindowID) {
        if let firstTabSibling = tabGroups.siblings(of: windowId)?.first {
            saveFocusedWindowInWorkspace(currentWorkspace, firstTabSibling)
        }
        tabGroups.remove(windowId)

        if let workspace = windowWorkspaceMap[windowId] {
            removeWindowFromList(workspace, windowId)
        }

        removeWindowFromFocusHistory(windowId)
        windowWorkspaceMap[windowId] = nil
    }

    // Commits the transition to the target workspace and returns the placements
    // the desktop must perform for it: the windows that belong to the target
    // workspace and everything else. `leavingFocusOn` is the window the workspace
    // being left should come back to.
    func switchTo(_ targetWorkspace: Int, leavingFocusOn windowId: CGWindowID?) -> (toActive: [CGWindowID], toStorage: [CGWindowID]) {
        if let windowId {
            saveFocusedWindowInWorkspace(currentWorkspace, windowId)
        }

        var toActive: [CGWindowID] = []
        var toStorage: [CGWindowID] = []

        for (windowId, workspace) in windowWorkspaceMap {
            if workspace == targetWorkspace {
                toActive.append(windowId)
            } else {
                toStorage.append(windowId)
            }
        }

        currentWorkspace = targetWorkspace

        return (toActive: toActive, toStorage: toStorage)
    }

    func tabSiblings(of windowId: CGWindowID) -> [CGWindowID]? {
        tabGroups.siblings(of: windowId)
    }

    // A workspace with no usable focus history falls back to the first window in
    // it, and that answer needs no recording to stay stable: the first window keeps
    // being the answer until it leaves the workspace, and every way of leaving
    // either purges it from the history or saves it somewhere else.
    func nextWindowToFocus() -> CGWindowID? {
        // Focus history is not pruned when a window changes workspace: this
        // membership check, the only read of it, is what keeps an entry left
        // behind by a window that moved away out of the answer.
        if let focusHistory = focusedWindows[currentWorkspace] {
            for windowId in focusHistory where windowWorkspaceMap[windowId] == currentWorkspace {
                return windowId
            }
        }

        return workspaceWindowsMap[currentWorkspace]?.first
    }

    private func assign(_ windowId: CGWindowID, to workspace: Int) {
        let previousWorkspace = windowWorkspaceMap[windowId]
        if previousWorkspace == workspace { return }

        if let previousWorkspace {
            removeWindowFromList(previousWorkspace, windowId)
        }

        workspaceWindowsMap[workspace, default: []].append(windowId)
        windowWorkspaceMap[windowId] = workspace
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
        for workspace in focusedWindows.keys {
            focusedWindows[workspace]?.removeAll { $0 == windowId }
        }
    }
}
