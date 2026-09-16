import Foundation

enum ConfigFile {
    private static let name = "ottowm"

    static func load(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        read: (URL) -> String? = { try? String(contentsOf: $0, encoding: .utf8) }
    ) -> Result<Config, ConfigError> {
        let path = XDGDirectory.url("XDG_CONFIG_HOME", orHome: ".config", environment: environment)
            .appendingPathComponent("\(name)/\(name)")

        guard let bundledPath = bundle.url(forResource: name, withExtension: nil) else {
            Log.config.error("the bundled configuration is missing, nothing is bound")
            return .success(Config([:]))
        }

        let text = read(path) ?? {
            Log.config.info("no configuration at \(path.path), using the bundled defaults")
            return read(bundledPath)
        }()

        guard let text else { return .success(Config([:])) }

        switch ConfigFileParser.parse(text) {
        case let .success(config):
            Log.config.notice("loaded \(path.path)")
            return .success(config)
        case let .failure(error):
            Log.config.error("\(path.path): \(error)")
            return .failure(error)
        }
    }
}
