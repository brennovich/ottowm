import CoreGraphics

// Tracks windows in their respective workspace via mappings of windows to workspaces.
final class Workspaces {
    private struct TabGroup {
        let representative: WindowSnapshot
        var windowIds: [CGWindowID]
    }

    var currentWorkspace = 1

    private var focusedWindows: [Int: [CGWindowID]] = [:]
    private var windowWorkspaceMap: [CGWindowID: Int] = [:]
    private var workspaceWindowsMap: [Int: [CGWindowID]] = [:]

    private var groups: [Int: TabGroup] = [:]
    private var windowToGroup: [CGWindowID: Int] = [:]
    private var nextGroupId = 1

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
        let isNewWindow = windowToGroup[window.id] == nil
        if isNewWindow {
            var existingGroupId: Int?

            if window.tabCount > 1 {
                for (groupId, group) in groups where window.isTab(of: group.representative) {
                    existingGroupId = groupId
                    break
                }
            }

            if let existingGroupId {
                groups[existingGroupId]?.windowIds.append(window.id)
                windowToGroup[window.id] = existingGroupId
            } else {
                let groupId = nextGroupId
                nextGroupId += 1
                groups[groupId] = TabGroup(representative: window, windowIds: [window.id])
                windowToGroup[window.id] = groupId
            }
        }

        assignGroup(windowToGroup[window.id]!, to: workspace)
        saveFocusedWindowInWorkspace(workspace, window.id)
    }

    func moveWindowToWorkspace(_ windowId: CGWindowID, _ workspace: Int) {
        if let groupId = windowToGroup[windowId] {
            assignGroup(groupId, to: workspace)
        } else {
            assign(windowId, to: workspace)
        }

        saveFocusedWindowInWorkspace(workspace, windowId)
    }

    func unregisterWindowById(_ windowId: CGWindowID) {
        if let groupId = windowToGroup[windowId] {
            groups[groupId]?.windowIds.removeAll { $0 == windowId }

            if let firstTabSibling = tabSiblings(of: windowId)?.first {
                saveFocusedWindowInWorkspace(currentWorkspace, firstTabSibling)
            }

            windowToGroup[windowId] = nil

            if groups[groupId]?.windowIds.isEmpty ?? false {
                groups[groupId] = nil
            }
        }

        if let workspace = windowWorkspaceMap[windowId] {
            removeWindowFromList(workspace, windowId)
        }

        removeWindowFromFocusHistory(windowId)
        windowWorkspaceMap[windowId] = nil
    }

    // Split the model's windows into the ones that belong to the target
    // workspace and everything else, for a transition between two workspaces.
    func categorizeWindowsForTransition(_ targetWorkspace: Int) -> (toActive: [CGWindowID], toStorage: [CGWindowID]) {
        var toActive: [CGWindowID] = []
        var toStorage: [CGWindowID] = []

        for (windowId, workspace) in windowWorkspaceMap {
            if workspace == targetWorkspace {
                toActive.append(windowId)
            } else {
                toStorage.append(windowId)
            }
        }

        return (toActive: toActive, toStorage: toStorage)
    }

    func tabSiblings(of windowId: CGWindowID) -> [CGWindowID]? {
        guard let groupId = windowToGroup[windowId] else { return nil }

        let siblings = (groups[groupId]?.windowIds ?? []).filter { $0 != windowId }
        return siblings.isEmpty ? nil : siblings
    }

    func prepareWindowToBeFocusedOnCurrentWorkspace() -> CGWindowID? {
        if let focusHistory = focusedWindows[currentWorkspace] {
            for windowId in focusHistory where windowWorkspaceMap[windowId] == currentWorkspace {
                return windowId
            }
        }

        let windows = workspaceWindowsMap[currentWorkspace] ?? []
        if let first = windows.first {
            saveFocusedWindowInWorkspace(currentWorkspace, first)
            return first
        }

        return nil
    }

    private func assign(_ windowId: CGWindowID, to workspace: Int) {
        let previousWorkspace = windowWorkspaceMap[windowId]
        if previousWorkspace == workspace { return }

        if let previousWorkspace {
            removeWindowFromList(previousWorkspace, windowId)
            focusedWindows[previousWorkspace]?.removeAll { $0 == windowId }
        }

        workspaceWindowsMap[workspace, default: []].append(windowId)
        windowWorkspaceMap[windowId] = workspace
    }

    private func assignGroup(_ groupId: Int, to workspace: Int) {
        for windowId in groups[groupId]?.windowIds ?? [] {
            assign(windowId, to: workspace)
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
