import CoreGraphics

struct Config: Equatable {
    private let bindingsByKeyCode: [Int64: [KeyCombo: Binding]]

    init(_ bindings: [KeyCombo: Binding]) {
        bindingsByKeyCode = bindings.reduce(into: [:]) {
            $0[$1.key.keyCode, default: [:]][$1.key] = $1.value
        }
    }

    func binding(keyCode: Int64, flags: CGEventFlags) -> Binding? {
        bindingsByKeyCode[keyCode]?.first { $0.key.matches(flags) }?.value
    }
}
