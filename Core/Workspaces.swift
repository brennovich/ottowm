import CoreGraphics

/// Model that maps windows to their respective workspace, keeping the focus history of
/// each workspace and the active workspace.
final class Workspaces {
    private(set) var current = 1

    private var workspaces: [Int: Workspace] = [:]

    private var tabGroups: TabGroups

    init(tabCount: @escaping (CGWindowID) -> Int) {
        tabGroups = TabGroups(tabCount: tabCount)
    }

    var allWindowIds: Set<CGWindowID> {
        Set(workspaces.values.flatMap(\.windowIds))
    }

    func recordFocus(on windowId: CGWindowID, in workspace: Int) {
        workspaces[workspace]?.recordFocus(on: windowId)
    }

    func workspace(for windowId: CGWindowID) -> Int? {
        workspaces.first { $0.value.windowIds.contains(windowId) }?.key
    }

    func windowIds(in workspace: Int) -> [CGWindowID] {
        workspaces[workspace]?.windowIds ?? []
    }

    /// Assigns the window to `workspace`, or to the workspace its tab group already sits in.
    ///
    /// A tab group moves as one unit. A window joining a group lands where the group is;
    /// the group does not follow the window.
    /// - Returns: the workspace the window landed in.
    @discardableResult
    func assign(_ window: WindowSnapshot, to workspace: Int) -> Int {
        tabGroups.add(window)
        let target = tabGroups.siblings(of: window.id).lazy.compactMap { self.workspace(for: $0) }.first ?? workspace
        assignTabGroup(of: window.id, to: target)
        recordFocus(on: window.id, in: target)
        return target
    }

    func move(_ windowId: CGWindowID, to workspace: Int) {
        assignTabGroup(of: windowId, to: workspace)
        recordFocus(on: windowId, in: workspace)
    }

    /// Whether the window is a tab of a group that is already managed.
    func hasTabGroup(for window: WindowSnapshot) -> Bool {
        tabGroups.hasGroup(for: window)
    }

    /// The windows macOS minimizes, restores and moves together with this one. A tab group
    /// is one window to macOS.
    func tabGroupMembers(of windowId: CGWindowID) -> [CGWindowID] {
        tabGroups.members(of: windowId)
    }

    /// Drops the window from its workspace and from the focus history.
    /// - Returns: `true` if a surviving tab sibling took the focus, so no other window
    ///   needs it.
    @discardableResult
    func remove(_ windowId: CGWindowID) -> Bool {
        var focusSettled = false
        if let firstTabSibling = tabGroups.siblings(of: windowId).first,
           let siblingWorkspace = workspace(for: firstTabSibling) {
            recordFocus(on: firstTabSibling, in: siblingWorkspace)
            focusSettled = true
        }
        tabGroups.remove(windowId)

        if let workspace = workspace(for: windowId) {
            workspaces[workspace]?.remove(windowId)
        }
        return focusSettled
    }

    func switchTo(_ targetWorkspace: Int, leavingFocusOn windowId: CGWindowID?) -> (activating: [CGWindowID], parking: [CGWindowID]) {
        let placement = (activating: [CGWindowID](), parking: [CGWindowID]())
        guard targetWorkspace != current else { return placement }

        if let windowId {
            recordFocus(on: windowId, in: current)
        }
        current = targetWorkspace

        return workspaces.reduce(into: placement) { p, e in
            if e.key == targetWorkspace {
                p.activating.append(contentsOf: e.value.windowIds)
            } else {
                p.parking.append(contentsOf: e.value.windowIds)
            }
        }
    }

    /// The window to focus in the current workspace.
    var nextWindowToFocus: CGWindowID? {
        workspaces[current]?.nextWindowToFocus
    }

    private func assignTabGroup(of windowId: CGWindowID, to workspace: Int) {
        for memberId in tabGroups.members(of: windowId) {
            if let previousWorkspace = self.workspace(for: memberId) {
                guard previousWorkspace != workspace else { continue }
                workspaces[previousWorkspace]?.remove(memberId)
            }

            workspaces[workspace, default: Workspace()].add(memberId)
        }
    }
}
