enum Binding: Equatable {
    case action(Action)
    case quit
    case restart
    case about

    /// Whether a held key fires the binding again on every autorepeat. A toggle would flip back.
    var repeats: Bool {
        switch self {
        case .action: true
        case .quit, .restart, .about: false
        }
    }

    static func parse(_ text: String) -> Result<Binding, ConfigError.Reason> {
        let parts = text.split(separator: " ")

        guard let word = parts.first, let binding = bindingsByWord[String(word)] else {
            return Action.parse(text).map(Binding.action)
        }
        guard parts.count == 1 else { return .failure(.malformedAction(text)) }

        return .success(binding)
    }

    private static let bindingsByWord: [String: Binding] = [
        "quit": .quit,
        "restart": .restart,
        "about": .about,
    ]
}
