enum Direction: String, CaseIterable {
    case north, east, south, west

    var isVertical: Bool { self == .north || self == .south }
}
