import CoreGraphics

/// Where a managed window sits on the desktop.
enum Placement: Equatable {
    case active
    case storage
}

/// What placing one window leaves for the model to record.
enum PlacementOutcome: Hashable {
    /// The window sits at the hidden edge, owed `frame` back on screen.
    case parked(CGWindowID, owing: CGRect)
    /// The window is on screen and owes nothing.
    case onScreen(CGWindowID)
    /// The window no longer exists.
    case gone(CGWindowID)
}
