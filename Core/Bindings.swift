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

    func reload() {
        guard case let .success(config) = load() else {
            Log.app.error("unable to load a valid config, keeping the bindings already up")
            return
        }

        current.stop()
        current = tap(config)
        start()
        Log.app.notice("config reloaded")
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
