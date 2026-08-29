import CoreGraphics

/// macOS reports each tab as a standalone window, with no relation between
/// them, so a group is inferred from the window it was opened around and tracked
/// from there as tabs open and close.
struct TabGroups {
    private static let yTolerance: CGFloat = 10

    private struct Group {
        let representative: WindowSnapshot
        var windowIds: [CGWindowID]
    }

    private let tabCount: (CGWindowID) -> Int
    private var groups: [Int: Group] = [:]
    private var windowToGroup: [CGWindowID: Int] = [:]

    /// A group outlives its representative window, and macOS reuses window ids, so a group
    /// keyed by that id could be taken over by an unrelated window.
    private var nextGroupId = 1

    init(tabCount: @escaping (CGWindowID) -> Int) {
        self.tabCount = tabCount
    }

    /// Joins the group whose representative this window is a tab of, or opens a new
    /// one around it.
    mutating func add(_ window: WindowSnapshot) {
        guard windowToGroup[window.id] == nil else { return }

        let groupId = group(representing: window) ?? openGroup(around: window)
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

    private func group(representing window: WindowSnapshot) -> Int? {
        guard tabCount(window.id) > 1 else { return nil }

        return groups.first { isTab(window, of: $0.value.representative) }?.key
    }

    /// Membership is inferred from two windows sharing an application and a frame, with a
    /// tolerance on y (tab height).
    private func isTab(_ window: WindowSnapshot, of representative: WindowSnapshot) -> Bool {
        return window.appName == representative.appName
            && window.frame.origin.x == representative.frame.origin.x
            && abs(window.frame.origin.y - representative.frame.origin.y) <= Self.yTolerance
            && window.frame.width == representative.frame.width
            && window.frame.height == representative.frame.height
    }
}
