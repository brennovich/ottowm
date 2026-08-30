import Foundation

enum ConfigFile {
    private static let name = "ottowm"

    static func load(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        read: (URL) -> String? = { try? String(contentsOf: $0, encoding: .utf8) }
    ) -> Result<Config, ConfigError> {
        func value(_ name: String) -> String? { environment[name].flatMap { $0.isEmpty ? nil : $0 } }

        let home = value("HOME") ?? NSHomeDirectory()
        let directory = value("XDG_CONFIG_HOME") ?? "\(home)/.config"
        let path = URL(fileURLWithPath: directory.hasPrefix("~/") ? home + directory.dropFirst() : directory)
            .appendingPathComponent("\(name)/\(name)")

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
}
