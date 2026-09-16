import CoreGraphics

/// What the state file holds. A window id holds for the length of a login session, so the
/// saved windows are found again by id.
struct SavedState: Codable, Equatable {
    let display: Display
    let workspaces: Workspaces.Record
    let parkedWindows: [ParkedWindow]
    let originalFrames: [CGWindowID: CGRect]
    let displayLayouts: [DisplayID: [CGWindowID: CGRect]]

    func keeping(_ windowIds: Set<CGWindowID>) -> SavedState {
        SavedState(
            display: display,
            workspaces: workspaces.keeping(windowIds),
            parkedWindows: parkedWindows.filter { windowIds.contains($0.windowId) },
            originalFrames: originalFrames.filter { windowIds.contains($0.key) },
            displayLayouts: displayLayouts.mapValues { $0.filter { windowIds.contains($0.key) } }
        )
    }
}
