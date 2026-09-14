import Foundation

enum ConfigFileParser {
    private typealias Settings = (bindings: [KeyCombo: Binding], showsPager: Bool)

    static func parse(_ text: String) -> Result<Config, ConfigError> {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { (number: $0.offset + 1, text: $0.element.prefix { $0 != "#" }.trimmed) }
            .filter { !$0.text.isEmpty }
            .reduce(.success((bindings: [:], showsPager: true))) { (acc: Result<Settings, ConfigError>, line) in
                acc.flatMap { settings in
                    guard let separator = line.text.range(of: "="),
                          case let key = line.text[..<separator.lowerBound].trimmed, !key.isEmpty
                    else { return .failure(ConfigError(line: line.number, reason: .syntax(line.text))) }

                    return parse(key, line.text[separator.upperBound...].trimmed, into: settings)
                        .mapError { ConfigError(line: line.number, reason: $0) }
                }
            }
            .map { Config($0.bindings, showsPager: $0.showsPager) }
    }

    private static func parse(_ key: String, _ value: String, into settings: Settings) -> Result<Settings, ConfigError.Reason> {
        guard key == "pager" else {
            return KeyCombo.parse(key)
                .flatMap { combo in Binding.parse(value).map { [combo: $0] } }
                .map { (bindings: settings.bindings.merging($0, uniquingKeysWith: { _, new in new }), showsPager: settings.showsPager) }
        }

        guard value == "on" || value == "off" else { return .failure(.invalidPager(value)) }

        return .success((bindings: settings.bindings, showsPager: value == "on"))
    }
}

private extension StringProtocol {
    var trimmed: String { trimmingCharacters(in: .whitespaces) }
}
