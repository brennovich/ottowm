import CoreGraphics

struct Config: Equatable {
    static let defaultSpacing: CGFloat = 15

    /// `system` draws the tab with the system material, `classic` draws it black.
    enum PagerStyle: String, CaseIterable {
        case system, classic
    }

    let showsPager: Bool
    let pagerStyle: PagerStyle
    let spacing: CGFloat
    private let bindingsByKeyCode: [Int64: [KeyCombo: Binding]]

    init(
        _ bindings: [KeyCombo: Binding],
        showsPager: Bool = true,
        pagerStyle: PagerStyle = .system,
        spacing: CGFloat = Config.defaultSpacing
    ) {
        self.showsPager = showsPager
        self.pagerStyle = pagerStyle
        self.spacing = spacing
        bindingsByKeyCode = bindings.reduce(into: [:]) {
            $0[$1.key.keyCode, default: [:]][$1.key] = $1.value
        }
    }

    func binding(keyCode: Int64, flags: CGEventFlags) -> Binding? {
        bindingsByKeyCode[keyCode]?.first { $0.key.matches(flags) }?.value
    }
}
