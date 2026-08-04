enum Action: Equatable {
    case switchToWorkspace(Int)
    case moveWindowToWorkspace(Int)

    static func parse(_ text: String) -> Result<Action, ConfigError.Reason> {
        let parts = text.split(separator: " ").map(String.init)

        guard parts.count == 2 else { return .failure(.malformedAction(text)) }
        guard let verb = parts.first else { return .failure(.malformedAction(text)) }
        guard let action = actionsByVerb[verb] else { return .failure(.unknownAction(verb)) }
        guard let workspace = Int(parts[1]), workspace >= 1 else {
            return .failure(.invalidWorkspace(parts[1]))
        }

        return .success(action(workspace))
    }

    private static let actionsByVerb: [String: (Int) -> Action] = [
        "switch-to-workspace": Action.switchToWorkspace,
        "move-window-to-workspace": Action.moveWindowToWorkspace,
    ]
}
