import Foundation

enum ConfigFileParser {
    static func parse(_ text: String) -> Result<Config, ConfigError> {
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { (number: $0.offset + 1, text: $0.element.prefix { $0 != "#" }.trimmed) }
            .filter { !$0.text.isEmpty }
            .reduce(.success([:])) { (acc: Result<[KeyCombo: Action], ConfigError>, line) in
                acc.flatMap { bindings in
                    binding(in: line.text)
                        .map { bindings.merging($0, uniquingKeysWith: { _, new in new }) }
                        .mapError { ConfigError(line: line.number, reason: $0) }
                }
            }
            .map(Config.init)
    }

    private static func binding(in line: String) -> Result<[KeyCombo: Action], ConfigError.Reason> {
        guard let parts = line.range(of: "=") else { return .failure(.syntax(line)) }
        guard case let key = line[..<parts.lowerBound].trimmed, !key.isEmpty else { return .failure(.syntax(line)) }

        return KeyCombo.parse(key).flatMap { kc in Action.parse(line[parts.upperBound...].trimmed).map { [kc: $0] }}
    }
}

private extension StringProtocol {
    var trimmed: String { trimmingCharacters(in: .whitespaces) }
}
