/// The way a focus move travels across the desktop.
enum Direction: String, CaseIterable {
    case north, east, south, west

    /// North and south travel the y axis, east and west the x axis.
    var isVertical: Bool { self == .north || self == .south }
}
