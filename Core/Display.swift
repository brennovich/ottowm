import CoreGraphics

struct DisplayID: Hashable {
    let rawValue: String
}

struct Display: Equatable {
    let id: DisplayID
    let fullFrame: CGRect
    let visibleFrame: CGRect
}
