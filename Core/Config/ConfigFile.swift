import Foundation

enum ConfigFile {
    private static let name = "ottowm"

    static func load(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        read: (URL) -> String? = { try? String(contentsOf: $0, encoding: .utf8) }
    ) -> Result<Config, ConfigError> {
        let path = userPath(environment: environment)

        guard let text = read(path) else {
            Log.config.info("no configuration at \(path.path), using the bundled defaults")
            return .success(bundled(bundle: bundle, read: read))
        }

        let config = ConfigFileParser.parse(text)
        switch config {
        case .success: Log.config.notice("loaded \(path.path)")
        case let .failure(error): Log.config.error("\(path.path): \(error)")
        }

        return config
    }

    static func userPath(environment: [String: String]) -> URL {
        func value(_ name: String) -> String? { environment[name].flatMap { $0.isEmpty ? nil : $0 } }

        let home = value("HOME") ?? NSHomeDirectory()
        let path = value("XDG_CONFIG_HOME") ?? "\(home)/.config"
        
        return URL(fileURLWithPath: path.hasPrefix("~/") ? home + path.dropFirst() : path)
            .appendingPathComponent("\(name)/\(name)")
    }

    private static func bundled(bundle: Bundle, read: (URL) -> String?) -> Config {
        guard let path = bundle.url(forResource: name, withExtension: nil),
              let text = read(path),
              case let .success(config) = ConfigFileParser.parse(text)
        else {
            Log.config.error("the bundled configuration is missing or unparseable, nothing is bound")
            return Config([:])
        }

        return config
    }
}
