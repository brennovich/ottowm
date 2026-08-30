import CoreGraphics

struct Config: Equatable {
    private let bindingsByKeyCode: [Int64: [KeyCombo: Action]]

    init(_ bindings: [KeyCombo: Action]) {
        bindingsByKeyCode = bindings.reduce(into: [:]) {
            $0[$1.key.keyCode, default: [:]][$1.key] = $1.value
        }
    }

    func action(keyCode: Int64, flags: CGEventFlags) -> Action? {
        bindingsByKeyCode[keyCode]?.first { $0.key.matches(flags) }?.value
    }
}
