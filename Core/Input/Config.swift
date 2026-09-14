import CoreGraphics

struct Config: Equatable {
    let showsPager: Bool
    private let bindingsByKeyCode: [Int64: [KeyCombo: Binding]]

    init(_ bindings: [KeyCombo: Binding], showsPager: Bool = true) {
        self.showsPager = showsPager
        bindingsByKeyCode = bindings.reduce(into: [:]) {
            $0[$1.key.keyCode, default: [:]][$1.key] = $1.value
        }
    }

    func binding(keyCode: Int64, flags: CGEventFlags) -> Binding? {
        bindingsByKeyCode[keyCode]?.first { $0.key.matches(flags) }?.value
    }
}
