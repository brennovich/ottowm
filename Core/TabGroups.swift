import CoreGraphics

// The windows macOS shows as tabs of one another. Membership is never exposed by
// the OS, so a group is inferred from the window it was opened around.
struct TabGroups {
    private static let yTolerance: CGFloat = 10

    private struct Group {
        let representative: WindowSnapshot
        var windowIds: [CGWindowID]
    }

    private var groups: [Int: Group] = [:]
    private var windowToGroup: [CGWindowID: Int] = [:]

    // Groups outlive their representative window and macOS recycles window ids, so a
    // group keyed by that id could be taken over by an unrelated new window.
    private var nextGroupId = 1

    // Joins the group whose representative this window is a tab of, or opens a new
    // one around it.
    mutating func add(_ window: WindowSnapshot, tabCount: Int) {
        guard windowToGroup[window.id] == nil else { return }

        let groupId = groupRepresenting(window, tabCount) ?? openGroup(around: window)
        groups[groupId]?.windowIds.append(window.id)
        windowToGroup[window.id] = groupId
    }

    private mutating func openGroup(around window: WindowSnapshot) -> Int {
        let groupId = nextGroupId
        nextGroupId += 1
        groups[groupId] = Group(representative: window, windowIds: [])

        return groupId
    }

    func members(of windowId: CGWindowID) -> [CGWindowID] {
        return windowToGroup[windowId].flatMap { groups[$0]?.windowIds } ?? [windowId]
    }

    func siblings(of windowId: CGWindowID) -> [CGWindowID] {
        return members(of: windowId).filter { $0 != windowId }
    }

    mutating func remove(_ windowId: CGWindowID) {
        guard let groupId = windowToGroup.removeValue(forKey: windowId),
              var group = groups[groupId] else { return }

        group.windowIds.removeAll { $0 == windowId }
        groups[groupId] = group.windowIds.isEmpty ? nil : group
    }

    private func groupRepresenting(_ window: WindowSnapshot, _ tabCount: Int) -> Int? {
        guard tabCount > 1 else { return nil }

        return groups.first { isTab(window, of: $0.value.representative) }?.key
    }

    // macOS does not report tab membership, so it is inferred from two windows sharing
    // an application and a frame, within a tolerance on y.
    private func isTab(_ window: WindowSnapshot, of representative: WindowSnapshot) -> Bool {
        return window.appName == representative.appName
            && window.frame.origin.x == representative.frame.origin.x
            && abs(window.frame.origin.y - representative.frame.origin.y) <= Self.yTolerance
            && window.frame.width == representative.frame.width
            && window.frame.height == representative.frame.height
    }
}
