enum Binding: Equatable {
    case action(Action)
    case quit
    case restart

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
    ]
}
