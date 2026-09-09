/// Reads the config OttoWM boots with, and offers the user a restart or a quit when it does
/// not parse: `.loaded` carries the config to bind, `.relaunching` means a new instance is
/// coming up, `.quit` that the alert was dismissed.
struct ConfigGate {
    enum Outcome: Equatable {
        case loaded(Config)
        case relaunching
        case quit
    }

    var read: () -> Result<Config, ConfigError> = { ConfigFile.load() }
    var ask: (ConfigError) -> ConfigAlert.Response = { ConfigAlert.ask($0, .boot) }
    let relaunch: () -> Void

    func load() -> Outcome {
        switch read() {
        case let .success(config): .loaded(config)
        case let .failure(error): recover(from: error)
        }
    }

    @discardableResult
    func recover(from error: ConfigError) -> Outcome {
        guard ask(error) == .restart else { return .quit }

        Log.config.notice("config rejected, relaunching")
        relaunch()

        return .relaunching
    }
}
