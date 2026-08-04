import Foundation

enum ConfigFile {
    private static let name = "ottowm"

    static func load(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        read: (URL) -> String? = { try? String(contentsOf: $0, encoding: .utf8) }
    ) -> Result<Config, ConfigError> {
        let path = userPath(environment: environment)

        guard let bundledPath = bundle.url(forResource: name, withExtension: nil) else {
            Log.config.error("the bundled configuration is missing, nothing is bound")
            return .success(Config([:]))
        }

        let text = read(path) ?? {
            Log.config.info("no configuration at \(path.path), using the bundled defaults")
            return read(bundledPath)
        }()

        return text
            .map(ConfigFileParser.parse)?
            .map { Log.config.notice("loaded \(path.path)"); return $0 }
            .mapError { Log.config.error("\(path.path): \($0)"); return $0 }
            ?? .success(Config([:]))
    }

    private static func userPath(environment: [String: String]) -> URL {
        func value(_ name: String) -> String? { environment[name].flatMap { $0.isEmpty ? nil : $0 } }

        let home = value("HOME") ?? NSHomeDirectory()
        let path = value("XDG_CONFIG_HOME") ?? "\(home)/.config"
        
        return URL(fileURLWithPath: path.hasPrefix("~/") ? home + path.dropFirst() : path)
            .appendingPathComponent("\(name)/\(name)")
    }
}
