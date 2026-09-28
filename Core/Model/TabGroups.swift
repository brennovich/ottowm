import CoreGraphics

struct TabGroups {
    private static let yTolerance: CGFloat = 10
    private static let sizeTolerance: CGFloat = 30

    private struct Group {
        let appName: String
        var windowIds: [CGWindowID]
    }

    private let tabCount: (CGWindowID) -> Int
    private let frame: (CGWindowID) -> CGRect?
    private var groups: [Int: Group] = [:]
    private var windowToGroup: [CGWindowID: Int] = [:]

    private var nextGroupId = 1

    init(tabCount: @escaping (CGWindowID) -> Int, frame: @escaping (CGWindowID) -> CGRect?) {
        self.tabCount = tabCount
        self.frame = frame
    }

    mutating func add(_ window: WindowSnapshot) {
        if let current = windowToGroup[window.id] {
            join(window, leaving: current)
            return
        }

        let groupId: Int
        if let opened = group(representing: window) {
            groupId = opened
        } else {
            groupId = nextGroupId
            nextGroupId += 1
            groups[groupId] = Group(appName: window.appName, windowIds: [])
        }

        groups[groupId]?.windowIds.append(window.id)
        windowToGroup[window.id] = groupId
    }

    func hasGroup(for window: WindowSnapshot) -> Bool {
        group(representing: window) != nil
    }

    func members(of windowId: CGWindowID) -> [CGWindowID] {
        windowToGroup[windowId].flatMap { groups[$0]?.windowIds } ?? [windowId]
    }

    func siblings(of windowId: CGWindowID) -> [CGWindowID] {
        members(of: windowId).filter { $0 != windowId }
    }

    mutating func remove(_ windowId: CGWindowID) {
        guard let groupId = windowToGroup.removeValue(forKey: windowId),
              var group = groups[groupId] else { return }

        group.windowIds.removeAll { $0 == windowId }
        groups[groupId] = group.windowIds.isEmpty ? nil : group
    }

    private func group(representing window: WindowSnapshot) -> Int? {
        let standing = groups.filter { entry in
            entry.value.appName == window.appName
                && entry.key != windowToGroup[window.id]
                && entry.value.windowIds.lazy.compactMap(frame).contains { stands(window, at: $0) }
        }
        guard !standing.isEmpty else { return nil }

        let tabs = tabCount(window.id)
        guard tabs > 1 else { return nil }

        return standing.first { $0.value.windowIds.count < tabs }?.key
    }

    private mutating func join(_ window: WindowSnapshot, leaving opened: Int) {
        guard groups[opened]?.windowIds.count == 1, let joined = group(representing: window) else { return }

        groups[opened] = nil
        groups[joined]?.windowIds.append(window.id)
        windowToGroup[window.id] = joined
    }

    private func stands(_ window: WindowSnapshot, at occupied: CGRect) -> Bool {
        window.frame.origin.x == occupied.origin.x
            && abs(window.frame.origin.y - occupied.origin.y) <= Self.yTolerance
            && abs(window.frame.width - occupied.width) <= Self.sizeTolerance
            && abs(window.frame.height - occupied.height) <= Self.sizeTolerance
    }
}
