/// ConfigGate reads the config OttoWM boots with, and offers the user to restart
/// or to quit when it does not parse.
///
/// - Returns:
///   - `.loaded`: the config to bind.
///   - `.relaunching`: a new instance is on its way up.
///   - `.quit`: the alert was dismissed.
struct ConfigGate {
    enum Outcome: Equatable {
        case loaded(Config)
        case relaunching
        case quit
    }

    var read: () -> Result<Config, ConfigError> = { ConfigFile.load() }
    var ask: (ConfigError) -> ConfigAlert.Response = ConfigAlert.ask
    let relaunch: () -> Void

    func load() -> Outcome {
        switch read() {
        case let .success(config):
            return .loaded(config)
        case let .failure(error):
            guard ask(error) == .restart else { return .quit }

            Log.config.notice("config rejected, relaunching")
            relaunch()

            return .relaunching
        }
    }
}
