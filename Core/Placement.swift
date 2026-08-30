import CoreGraphics

enum Placement: Equatable {
    case active
    case parked
}

enum PlacementOutcome: Hashable {
    case parked(CGWindowID, owing: CGRect)
    case activated(CGWindowID)
    case gone(CGWindowID)
}
