import CoreGraphics

struct DisplayID: Hashable {
    let rawValue: String
}

struct Display: Equatable {
    let id: DisplayID
    let fullFrame: CGRect
    let visibleFrame: CGRect
}

extension Display {
    var logDescription: String { "\(id.rawValue) \(fullFrame) visible \(visibleFrame)" }
}
