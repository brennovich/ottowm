import CoreGraphics

final class Workspaces {
    enum Membership: Equatable {
        case fullScreen(Int)
        case assigned(Int)
        case unassigned(Int)
    }

    private(set) var current = 1

    private var workspaces: [Int: Workspace] = [:]

    private(set) var fullScreenWindows: [CGWindowID: Int] = [:]

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

    func membership(of window: WindowSnapshot, whenNew fallback: Int) -> Membership {
        if let workspace = fullScreenWindows[window.id] { return .fullScreen(workspace) }
        if let assigned = workspace(for: window.id) { return .assigned(assigned) }
        return .unassigned(workspaceOfTabGroup(for: window) ?? fallback)
    }

    func recordFullScreen(_ windowId: CGWindowID, leaving workspace: Int) {
        fullScreenWindows[windowId] = workspace
    }

    @discardableResult
    func assign(_ window: WindowSnapshot, to workspace: Int) -> Int {
        let target = workspaceOfTabGroup(for: window) ?? fullScreenWindows[window.id] ?? workspace
        fullScreenWindows.removeValue(forKey: window.id)
        tabGroups.add(window)
        assignTabGroup(of: window.id, to: target)
        recordFocus(on: window.id, in: target)
        return target
    }

    func move(_ windowId: CGWindowID, to workspace: Int) {
        fullScreenWindows.removeValue(forKey: windowId)
        assignTabGroup(of: windowId, to: workspace)
        recordFocus(on: windowId, in: workspace)
    }

    func hasTabGroup(for window: WindowSnapshot) -> Bool {
        tabGroups.hasGroup(for: window)
    }

    func tabGroupMembers(of windowId: CGWindowID) -> [CGWindowID] {
        tabGroups.members(of: windowId)
    }

    @discardableResult
    func remove(_ windowId: CGWindowID) -> Bool {
        fullScreenWindows.removeValue(forKey: windowId)

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

    var nextWindowToFocus: CGWindowID? {
        workspaces[current]?.nextWindowToFocus
    }

    private func workspaceOfTabGroup(for window: WindowSnapshot) -> Int? {
        tabGroups.siblings(of: window).lazy.compactMap { self.workspace(for: $0) }.first
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
