final class Bindings {
    struct Tap {
        let start: () -> Bool
        let stop: () -> Void
    }

    private let load: () -> Result<Config, ConfigError>
    private let tap: (Config) -> Tap
    private var current: Tap
    private var handler: (Config) -> Void = { _ in }

    private(set) var isRunning = false
    /// The error of the last reload, nil once a reload succeeded.
    private(set) var lastError: ConfigError?

    init(
        config: Config,
        load: @escaping () -> Result<Config, ConfigError> = { ConfigFile.load() },
        tap: @escaping (Config) -> Tap
    ) {
        self.load = load
        self.tap = tap
        current = tap(config)
    }

    func startWatching(_ handler: @escaping (Config) -> Void) {
        self.handler = handler
    }

    func start() {
        isRunning = current.start()
        if !isRunning {
            Log.app.error("event tap creation failed (check Accessibility permission)")
        }
    }

    func stop() {
        current.stop()
        isRunning = false
    }

    /// - Returns: the error that left the bindings in place, or `nil` once the tap is over
    ///   the config just read.
    func reload() -> ConfigError? {
        switch load() {
        case let .success(config):
            current.stop()
            current = tap(config)
            start()
            Log.app.notice("config reloaded")
            lastError = nil
            handler(config)

            return nil
        case let .failure(error):
            Log.app.error("unable to load a valid config, keeping the bindings already up")
            lastError = error

            return error
        }
    }
}

extension Bindings {
    static func system(config: Config, handler: @escaping (Binding) -> Void) -> Bindings {
        Bindings(config: config) { config in
            let hotkeys = Hotkeys(keyCodeMatcher: config.binding, handler: handler)
            return Tap(start: hotkeys.start, stop: hotkeys.stop)
        }
    }
}
