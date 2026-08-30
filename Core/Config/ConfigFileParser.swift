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
                    guard let separator = line.text.range(of: "="),
                          case let key = line.text[..<separator.lowerBound].trimmed, !key.isEmpty
                    else { return .failure(ConfigError(line: line.number, reason: .syntax(line.text))) }

                    return KeyCombo.parse(key)
                        .flatMap { combo in Action.parse(line.text[separator.upperBound...].trimmed).map { [combo: $0] } }
                        .map { bindings.merging($0, uniquingKeysWith: { _, new in new }) }
                        .mapError { ConfigError(line: line.number, reason: $0) }
                }
            }
            .map(Config.init)
    }
}

private extension StringProtocol {
    var trimmed: String { trimmingCharacters(in: .whitespaces) }
}
