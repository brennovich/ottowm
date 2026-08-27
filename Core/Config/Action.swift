enum Action: Equatable {
    case switchToWorkspace(Int)
    case moveWindowToWorkspace(Int)
    case focus(Direction)
    case quit
    case restart

    static func parse(_ text: String) -> Result<Action, ConfigError.Reason> {
        let parts = text.split(separator: " ").map(String.init)

        guard let verb = parts.first else { return .failure(.malformedAction(text)) }

        if let action = actionsByVerb[verb] {
            guard parts.count == 1 else { return .failure(.malformedAction(text)) }
            return .success(action)
        }

        guard let action = argumentActionsByVerb[verb] else { return .failure(.unknownAction(verb)) }
        guard parts.count == 2 else { return .failure(.malformedAction(text)) }

        return action(parts[1])
    }

    private static let actionsByVerb: [String: Action] = [
        "quit": .quit,
        "restart": .restart,
    ]

    private static let argumentActionsByVerb: [String: (String) -> Result<Action, ConfigError.Reason>] = [
        "switch-to-workspace": { workspace($0).map(Action.switchToWorkspace) },
        "move-window-to-workspace": { workspace($0).map(Action.moveWindowToWorkspace) },
        "focus": { direction($0).map(Action.focus) },
    ]

    private static func workspace(_ text: String) -> Result<Int, ConfigError.Reason> {
        guard let workspace = Int(text), workspace >= 1 else { return .failure(.invalidWorkspace(text)) }

        return .success(workspace)
    }

    private static func direction(_ text: String) -> Result<Direction, ConfigError.Reason> {
        guard let direction = Direction(rawValue: text) else { return .failure(.invalidDirection(text)) }

        return .success(direction)
    }
}
