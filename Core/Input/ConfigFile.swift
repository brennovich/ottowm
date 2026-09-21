import Foundation

enum ConfigFile {
    private static let name = "ottowm"

    static func path(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        XDGDirectory.url("XDG_CONFIG_HOME", orHome: ".config", environment: environment)
            .appendingPathComponent("\(name)/\(name)")
    }

    private static func bundledPath(_ bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: name, withExtension: nil)
    }

    /// Writes the bundled defaults to the user path, creating its directory. Nothing is written when the bundled
    /// file is missing.
    static func writeDefaults(bundle: Bundle = .main, environment: [String: String] = ProcessInfo.processInfo.environment) {
        let path = path(environment: environment)
        guard let bundledPath = bundledPath(bundle), let text = try? String(contentsOf: bundledPath, encoding: .utf8) else {
            return Log.config.error("the bundled configuration is missing, no file written")
        }

        do {
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: path, atomically: true, encoding: .utf8)
            Log.config.notice("wrote the bundled defaults to \(path.path)")
        } catch {
            Log.config.error("unable to write \(path.path): \(error.localizedDescription)")
        }
    }

    static func load(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        read: (URL) -> String? = { try? String(contentsOf: $0, encoding: .utf8) }
    ) -> Result<Config, ConfigError> {
        let path = path(environment: environment)

        guard let bundledPath = bundledPath(bundle) else {
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
