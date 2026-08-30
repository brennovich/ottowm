import CoreGraphics

struct TabGroups {
    private static let yTolerance: CGFloat = 10

    private struct Group {
        let representative: WindowSnapshot
        var windowIds: [CGWindowID]
    }

    private let tabCount: (CGWindowID) -> Int
    private var groups: [Int: Group] = [:]
    private var windowToGroup: [CGWindowID: Int] = [:]

    private var nextGroupId = 1

    init(tabCount: @escaping (CGWindowID) -> Int) {
        self.tabCount = tabCount
    }

    mutating func add(_ window: WindowSnapshot) {
        guard windowToGroup[window.id] == nil else { return }

        let groupId: Int
        if let opened = group(representing: window) {
            groupId = opened
        } else {
            groupId = nextGroupId
            nextGroupId += 1
            groups[groupId] = Group(representative: window, windowIds: [])
        }

        groups[groupId]?.windowIds.append(window.id)
        windowToGroup[window.id] = groupId
    }

    func hasGroup(for window: WindowSnapshot) -> Bool {
        return group(representing: window) != nil
    }

    func members(of windowId: CGWindowID) -> [CGWindowID] {
        return windowToGroup[windowId].flatMap { groups[$0]?.windowIds } ?? [windowId]
    }

    func siblings(of windowId: CGWindowID) -> [CGWindowID] {
        return members(of: windowId).filter { $0 != windowId }
    }

    func siblings(of window: WindowSnapshot) -> [CGWindowID] {
        guard windowToGroup[window.id] == nil else { return siblings(of: window.id) }

        return group(representing: window).flatMap { groups[$0]?.windowIds } ?? []
    }

    mutating func remove(_ windowId: CGWindowID) {
        guard let groupId = windowToGroup.removeValue(forKey: windowId),
              var group = groups[groupId] else { return }

        group.windowIds.removeAll { $0 == windowId }
        groups[groupId] = group.windowIds.isEmpty ? nil : group
    }

    private func group(representing window: WindowSnapshot) -> Int? {
        guard tabCount(window.id) > 1 else { return nil }

        return groups.first { entry in
            let representative = entry.value.representative

            return window.appName == representative.appName
                && window.frame.origin.x == representative.frame.origin.x
                && abs(window.frame.origin.y - representative.frame.origin.y) <= Self.yTolerance
                && window.frame.width == representative.frame.width
                && window.frame.height == representative.frame.height
        }?.key
    }
}
