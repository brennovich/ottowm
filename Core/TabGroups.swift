import CoreGraphics

// The windows macOS shows as tabs of one another. Membership is never exposed by
// the OS, so a group is inferred from the window it was opened around.
struct TabGroups {
    private struct Group {
        let representative: WindowSnapshot
        var windowIds: [CGWindowID]
    }

    private var groups: [Int: Group] = [:]
    private var windowToGroup: [CGWindowID: Int] = [:]
    // A group outlives its representative window, so groups cannot be keyed by
    // its id: macOS recycles window ids, and a new window inheriting a dead
    // representative's id would take over a group that still has members.
    private var nextGroupId = 1

    // Joins the group whose representative this window is a tab of, or opens a new
    // one around it. A window already in a group keeps it.
    mutating func add(_ window: WindowSnapshot) {
        guard windowToGroup[window.id] == nil else { return }

        if let groupId = groupRepresenting(window) {
            groups[groupId]?.windowIds.append(window.id)
            windowToGroup[window.id] = groupId
            return
        }

        groups[nextGroupId] = Group(representative: window, windowIds: [window.id])
        windowToGroup[window.id] = nextGroupId
        nextGroupId += 1
    }

    // The windows that move together with this one, itself included. A window in
    // no group moves alone.
    func members(of windowId: CGWindowID) -> [CGWindowID] {
        guard let groupId = windowToGroup[windowId], let group = groups[groupId] else { return [windowId] }

        return group.windowIds
    }

    func siblings(of windowId: CGWindowID) -> [CGWindowID]? {
        guard windowToGroup[windowId] != nil else { return nil }

        let siblings = members(of: windowId).filter { $0 != windowId }
        return siblings.isEmpty ? nil : siblings
    }

    mutating func remove(_ windowId: CGWindowID) {
        guard let groupId = windowToGroup[windowId] else { return }

        groups[groupId]?.windowIds.removeAll { $0 == windowId }
        windowToGroup[windowId] = nil

        if groups[groupId]?.windowIds.isEmpty ?? false {
            groups[groupId] = nil
        }
    }

    private func groupRepresenting(_ window: WindowSnapshot) -> Int? {
        guard window.tabCount > 1 else { return nil }

        for (groupId, group) in groups where window.isTab(of: group.representative) {
            return groupId
        }

        return nil
    }
}
