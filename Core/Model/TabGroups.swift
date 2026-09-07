import CoreGraphics

struct TabGroups {
    private static let yTolerance: CGFloat = 10
    /// Terminal fits a window to whole rows when a tab takes over, one row being 17pt at the
    /// default font, and the tab that goes to the background keeps the size the write left:
    /// a fill of 1090 is answered as 1090 by one tab and as 1083 by the other.
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

    /// A tab opens where its window stands now, so the group is matched on where a member
    /// is rather than where the group was first seen: a maximize between the two moves
    /// every tab of the window. A background tab answers the frame it had when it was last
    /// active, so every member is tried and the one that is where the window stands places
    /// the group.
    ///
    /// Two maximized windows stand at one frame, so the frame alone matches either group.
    /// A group already holding as many windows as the tab reports tabs is full, and the
    /// tab of the other window opens its own group. The group the window is already in is
    /// no candidate, so a window is never matched against itself.
    private func group(representing window: WindowSnapshot) -> Int? {
        let candidates = groups.filter { $0.value.appName == window.appName && $0.key != windowToGroup[window.id] }
        guard !candidates.isEmpty else { return nil }

        let tabs = tabCount(window.id)
        guard tabs > 1 else { return nil }

        return candidates.first { entry in
            guard entry.value.windowIds.count < tabs else { return false }

            return entry.value.windowIds.lazy.compactMap(frame).contains { stands(window, at: $0) }
        }?.key
    }

    /// Merging windows into tabs opens no window and posts no notification, so a window
    /// standing alone in the group it opened is matched again every time it is added: it
    /// joins the group of the window it was merged into, and the group it leaves is
    /// retired. A window that already has siblings keeps the group it is in.
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
