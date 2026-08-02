import Foundation

// The file a configuration is read from: the user's, or the copy bundled in the app when there
// is none.
enum ConfigFile {
    private static let name = "ottowm"

    // A file that is there but does not parse is the user's to fix, so it is reported rather
    // than papered over: the caller stops the app instead of binding keys nobody asked for.
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

    // $OTTOWM_CONFIG overrides everything; otherwise the XDG location, which is where a
    // dotfiles repository is expected to put it.
    static func userPath(environment: [String: String]) -> URL {
        func value(_ name: String) -> String? { environment[name].flatMap { $0.isEmpty ? nil : $0 } }

        let home = value("HOME") ?? NSHomeDirectory()
        func url(_ path: String) -> URL {
            URL(fileURLWithPath: path.hasPrefix("~/") ? home + path.dropFirst() : path)
        }

        if let override = value("OTTOWM_CONFIG") {
            return url(override)
        }

        return url(value("XDG_CONFIG_HOME") ?? "\(home)/.config")
            .appendingPathComponent("\(name)/\(name)")
    }

    static func bundledPath(in bundle: Bundle) -> URL? {
        bundle.url(forResource: name, withExtension: nil)
    }

    // Missing or unparseable means the app was built wrong, which the tests catch. At runtime a
    // headless agent is better off with no hotkeys than with no launch.
    private static func bundled(bundle: Bundle, read: (URL) -> String?) -> Config {
        guard let path = bundledPath(in: bundle),
              let text = read(path),
              case let .success(config) = ConfigFileParser.parse(text)
        else {
            Log.config.error("the bundled configuration is missing or unparseable, nothing is bound")
            return Config([:])
        }

        return config
    }
}
