final class Bindings {
    struct Tap {
        let start: () -> Bool
        let stop: () -> Void
    }

    private let load: () -> Result<Config, ConfigError>
    private let tap: (Config) -> Tap
    private var current: Tap

    init(
        config: Config,
        load: @escaping () -> Result<Config, ConfigError> = { ConfigFile.load() },
        tap: @escaping (Config) -> Tap
    ) {
        self.load = load
        self.tap = tap
        current = tap(config)
    }

    func start() {
        if !current.start() {
            Log.app.error("event tap creation failed (check Accessibility permission)")
        }
    }

    func stop() {
        current.stop()
    }

    /// - Returns: the error that kept the bindings already up in place, or `nil` once the
    /// tap is over the config just read.
    func reload() -> ConfigError? {
        switch load() {
        case let .success(config):
            current.stop()
            current = tap(config)
            start()
            Log.app.notice("config reloaded")

            return nil
        case let .failure(error):
            Log.app.error("unable to load a valid config, keeping the bindings already up")

            return error
        }
    }
}

extension Bindings {
    static func system(config: Config, handler: @escaping (Action) -> Void) -> Bindings {
        Bindings(config: config) { config in
            let hotkeys = Hotkeys(keyCodeMatcher: config.action, handler: handler)
            return Tap(start: hotkeys.start, stop: hotkeys.stop)
        }
    }
}
