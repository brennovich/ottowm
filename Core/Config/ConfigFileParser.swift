import Foundation

// The format a configuration is written in: one `key combo = action` per line.
enum ConfigFileParser {
    private typealias Binding = (combo: KeyCombo, action: Action)

    static func parse(_ text: String) -> Result<Config, ConfigError> {
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { (number: $0.offset + 1, text: $0.element.trimmed) }
            .filter { !$0.text.isEmpty }
            .filter { !$0.text.contains("#") }

        var bindings: [KeyCombo: Action] = [:]
        for line in lines {
            switch binding(in: line.text) {
            case let .failure(reason): return .failure(ConfigError(line: line.number, reason: reason))
            case let .success(binding): bindings[binding.combo] = binding.action
            }
        }

        return .success(Config(bindings))
    }

    private static func binding(in line: String) -> Result<Binding, ConfigError.Reason> {
        guard let assignment = line.firstRange(of: "=") else { return .failure(.syntax(line)) }

        let key = line[..<assignment.lowerBound].trimmed
        let action = line[assignment.upperBound...].trimmed
        guard !key.isEmpty else { return .failure(.syntax(line)) }

        return KeyCombo.parse(key).flatMap { c in Action.parse(action).map { a in (combo: c, action: a) }}
    }
}

private extension StringProtocol {
    var trimmed: String { trimmingCharacters(in: .whitespaces) }
}
