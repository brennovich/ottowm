import CoreGraphics

enum Action: Equatable {
    case switchToWorkspace(Int)
    case moveWindowToWorkspace(Int)
    case focus(Direction)
    case moveWindow(Step)
    case quit
    case restart

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

    private static let defaultStep: CGFloat = 15

    private static let actionsByVerb: [String: Action] = [
        "quit": .quit,
        "restart": .restart,
    ]

    private static let argumentActionsByVerb: [String: (
        arity: ClosedRange<Int>,
        parse: ([String]) -> Result<Action, ConfigError.Reason>
    )] = [
        "switch-to-workspace": (1 ... 1, { workspace($0[0]).map(Action.switchToWorkspace) }),
        "move-window-to-workspace": (1 ... 1, { workspace($0[0]).map(Action.moveWindowToWorkspace) }),
        "focus": (1 ... 1, { direction($0[0]).map(Action.focus) }),
        "move-window": (1 ... 2, moveWindow),
    ]

    private static func moveWindow(_ arguments: [String]) -> Result<Action, ConfigError.Reason> {
        direction(arguments[0]).flatMap { direction in
            points(arguments.count == 2 ? arguments[1] : nil)
                .map { .moveWindow(Step(direction: direction, points: $0)) }
        }
    }

    private static func workspace(_ text: String) -> Result<Int, ConfigError.Reason> {
        guard let workspace = Int(text), workspace >= 1 else { return .failure(.invalidWorkspace(text)) }

        return .success(workspace)
    }

    private static func direction(_ text: String) -> Result<Direction, ConfigError.Reason> {
        guard let direction = Direction(rawValue: text) else { return .failure(.invalidDirection(text)) }

        return .success(direction)
    }

    private static func points(_ text: String?) -> Result<CGFloat, ConfigError.Reason> {
        guard let text else { return .success(defaultStep) }
        guard let points = Int(text), points >= 1 else { return .failure(.invalidStep(text)) }

        return .success(CGFloat(points))
    }
}
