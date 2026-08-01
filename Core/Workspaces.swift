import CoreGraphics

// Tracks windows in their respective workspace via mappings of windows to workspace.
final class Workspaces {
    private struct TabGroup {
        let representative: WindowSnapshot
        var windowIds: [CGWindowID]
    }

    private var focusedWindows: [Int: [CGWindowID]] = [:]
    private var windowVirtualSpaceMap: [CGWindowID: Int] = [:]
    private var virtualSpaceWindowsMap: [Int: [CGWindowID]] = [:]
    private var currentVirtualSpace = 1

    private var groups: [Int: TabGroup] = [:]
    private var windowToGroup: [CGWindowID: Int] = [:]
    private var nextGroupId = 1

    func saveFocusedWindowInVirtualSpace(_ virtualSpace: Int, _ windowId: CGWindowID?) {
        guard let windowId else { return }

        var focusHistory = focusedWindows[virtualSpace] ?? []
        focusHistory.removeAll { $0 == windowId }
        focusHistory.insert(windowId, at: 0)
        focusedWindows[virtualSpace] = focusHistory
    }

    func getVirtualSpaceForWindow(_ windowId: CGWindowID) -> Int? {
        windowVirtualSpaceMap[windowId]
    }

    func getWindowsInVirtualSpace(_ virtualSpace: Int) -> [CGWindowID] {
        virtualSpaceWindowsMap[virtualSpace] ?? []
    }

    func assignWindowToSpace(_ window: WindowSnapshot, _ virtualSpace: Int) {
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

        assignGroupToVirtualSpace(windowToGroup[window.id]!, virtualSpace)
        saveFocusedWindowInVirtualSpace(virtualSpace, window.id)
    }

    func moveWindowToVirtualSpace(_ windowId: CGWindowID, _ virtualSpace: Int) {
        if let groupId = windowToGroup[windowId] {
            assignGroupToVirtualSpace(groupId, virtualSpace)
        } else {
            assignWindowToVirtualSpace(windowId, virtualSpace)
        }

        saveFocusedWindowInVirtualSpace(virtualSpace, windowId)
    }

    func unregisterWindowById(_ windowId: CGWindowID) {
        if let groupId = windowToGroup[windowId] {
            groups[groupId]?.windowIds.removeAll { $0 == windowId }

            if let tabSiblings = getTabSiblingsBeforeDestruction(windowId) {
                saveFocusedWindowInVirtualSpace(getCurrentVirtualSpace(), tabSiblings.first)
            }

            windowToGroup[windowId] = nil

            if groups[groupId]?.windowIds.isEmpty ?? false {
                groups[groupId] = nil
            }
        }

        if let virtualSpace = windowVirtualSpaceMap[windowId] {
            removeWindowFromList(virtualSpace, windowId)
        }

        removeWindowFromFocusHistory(windowId)
        windowVirtualSpaceMap[windowId] = nil
    }

    // Split the model's windows into the ones that belong to the target virtual
    // space and everything else, for a transition between two native spaces.
    func categorizeWindowsForTransition(_ targetVirtualSpace: Int) -> (toActive: [CGWindowID], toStorage: [CGWindowID]) {
        var toActive: [CGWindowID] = []
        var toStorage: [CGWindowID] = []

        for (windowId, virtualSpace) in windowVirtualSpaceMap {
            if virtualSpace == targetVirtualSpace {
                toActive.append(windowId)
            } else {
                toStorage.append(windowId)
            }
        }

        return (toActive: toActive, toStorage: toStorage)
    }

    func allWindowIds() -> Set<CGWindowID> {
        Set(windowVirtualSpaceMap.keys)
    }

    func getCurrentVirtualSpace() -> Int {
        currentVirtualSpace
    }

    func setCurrentVirtualSpace(_ virtualSpace: Int) {
        currentVirtualSpace = virtualSpace
    }

    func getTabSiblingsBeforeDestruction(_ windowId: CGWindowID) -> [CGWindowID]? {
        guard let groupId = windowToGroup[windowId] else { return nil }

        let siblings = (groups[groupId]?.windowIds ?? []).filter { $0 != windowId }
        return siblings.isEmpty ? nil : siblings
    }

    func prepareWindowToBeFocusedOnCurrentVirtualSpace() -> CGWindowID? {
        if let focusHistory = focusedWindows[currentVirtualSpace] {
            for windowId in focusHistory where windowVirtualSpaceMap[windowId] == currentVirtualSpace {
                return windowId
            }
        }

        let windows = virtualSpaceWindowsMap[currentVirtualSpace] ?? []
        if let first = windows.first {
            saveFocusedWindowInVirtualSpace(currentVirtualSpace, first)
            return first
        }

        return nil
    }

    private func assignWindowToVirtualSpace(_ windowId: CGWindowID, _ virtualSpace: Int) {
        let previousVirtualSpace = windowVirtualSpaceMap[windowId]
        if previousVirtualSpace == virtualSpace { return }

        if let previousVirtualSpace {
            removeWindowFromList(previousVirtualSpace, windowId)
            focusedWindows[previousVirtualSpace]?.removeAll { $0 == windowId }
        }

        virtualSpaceWindowsMap[virtualSpace, default: []].append(windowId)
        windowVirtualSpaceMap[windowId] = virtualSpace
    }

    private func assignGroupToVirtualSpace(_ groupId: Int, _ virtualSpace: Int) {
        for windowId in groups[groupId]?.windowIds ?? [] {
            assignWindowToVirtualSpace(windowId, virtualSpace)
        }
    }

    private func removeWindowFromList(_ virtualSpace: Int, _ windowId: CGWindowID) {
        virtualSpaceWindowsMap[virtualSpace]?.removeAll { $0 == windowId }
    }

    private func removeWindowFromFocusHistory(_ windowId: CGWindowID) {
        for virtualSpace in focusedWindows.keys {
            focusedWindows[virtualSpace]?.removeAll { $0 == windowId }
        }
    }
}
