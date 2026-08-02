import CoreGraphics

// The bindings the user configured, indexed by key code because the lookup runs inside the
// event tap callback, which macOS disables if it does not return promptly.
struct Config: Equatable {
    private let bindingsByKeyCode: [Int64: [KeyCombo: Action]]

    init(_ bindings: [KeyCombo: Action]) {
        bindingsByKeyCode = bindings.reduce(into: [:]) { indexed, binding in
            indexed[binding.key.keyCode, default: [:]][binding.key] = binding.value
        }
    }

    func action(keyCode: Int64, flags: CGEventFlags) -> Action? {
        bindingsByKeyCode[keyCode]?.first { $0.key.matches(flags) }?.value
    }
}
