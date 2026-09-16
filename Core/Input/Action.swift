enum Action: Equatable {
    case switchToWorkspace(Int)
    case moveWindowToWorkspace(Int)
    case focus(Direction)
    case moveWindow(Direction)
    case resize(Resize.Change)
    case centerWindow
    case maximize
    case tile(Direction)

    static func parse(_ text: String) -> Result<Action, ConfigError.Reason> {
        let parts = text.split(separator: " ").map(String.init)

        guard let verb = parts.first else { return .failure(.malformedAction(text)) }

        if let action = actionsByVerb[verb] {
            guard parts.count == 1 else { return .failure(.malformedAction(text)) }
            return .success(action)
        }

        let arguments = Array(parts.dropFirst())
        guard let action = argumentActionsByVerb[verb] else { return .failure(.unknownAction(verb)) }
        guard action.arity.contains(arguments.count) else { return .failure(.malformedAction(text)) }

        return action.parse(arguments)
    }

    private static let actionsByVerb: [String: Action] = [
        "center-window": .centerWindow,
        "maximize": .maximize,
    ]

    private static let argumentActionsByVerb: [String: (
        arity: ClosedRange<Int>,
        parse: ([String]) -> Result<Action, ConfigError.Reason>
    )] = [
        "switch-to-workspace": (1 ... 1, { workspace($0[0]).map(Action.switchToWorkspace) }),
        "move-window-to-workspace": (1 ... 1, { workspace($0[0]).map(Action.moveWindowToWorkspace) }),
        "focus": (1 ... 1, { word($0[0], or: ConfigError.Reason.invalidDirection).map(Action.focus) }),
        "tile": (1 ... 1, { word($0[0], or: ConfigError.Reason.invalidDirection).map(Action.tile) }),
        "move-window": (1 ... 1, { word($0[0], or: ConfigError.Reason.invalidDirection).map(Action.moveWindow) }),
        "resize": (1 ... 1, { word($0[0], or: ConfigError.Reason.invalidResize).map(Action.resize) }),
    ]

    private static func workspace(_ text: String) -> Result<Int, ConfigError.Reason> {
        guard let workspace = Int(text), workspace >= 1 else { return .failure(.invalidWorkspace(text)) }

        return .success(workspace)
    }

    private static func word<Word: RawRepresentable>(
        _ text: String,
        or reason: (String) -> ConfigError.Reason
    ) -> Result<Word, ConfigError.Reason> where Word.RawValue == String {
        guard let word = Word(rawValue: text) else { return .failure(reason(text)) }

        return .success(word)
    }
}
