import CoreGraphics

/// What the state file holds of one display. A window id holds for the length of a login
/// session, so the saved windows are found again by id.
struct SavedState: Codable, Equatable {
    let display: Display
    let workspaces: Workspaces.Record
    let parkedWindows: [CGWindowID: CGRect]
    let originalFrames: [CGWindowID: CGRect]

    func keeping(_ windowIds: Set<CGWindowID>) -> SavedState {
        SavedState(
            display: display,
            workspaces: workspaces.keeping(windowIds),
            parkedWindows: parkedWindows.filter { windowIds.contains($0.key) },
            originalFrames: originalFrames.filter { windowIds.contains($0.key) }
        )
    }
}

/// What the state file holds: the state of each display, and the layouts all displays share.
struct SavedSession: Codable, Equatable {
    let displays: [SavedState]
    let layouts: [DisplayID: [CGWindowID: CGRect]]
}
