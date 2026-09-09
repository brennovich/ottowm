import CoreGraphics

enum Action: Equatable {
    case switchToWorkspace(Int)
    case moveWindowToWorkspace(Int)
    case focus(Direction)
    case moveWindow(Step)
    case resize(Resize)
    case centerWindow
    case toggleMaximize
    case fill(Direction)

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
        "center-window": .centerWindow,
        "toggle-maximize": .toggleMaximize,
    ]

    private static let argumentActionsByVerb: [String: (
        arity: ClosedRange<Int>,
        parse: ([String]) -> Result<Action, ConfigError.Reason>
    )] = [
        "switch-to-workspace": (1 ... 1, { workspace($0[0]).map(Action.switchToWorkspace) }),
        "move-window-to-workspace": (1 ... 1, { workspace($0[0]).map(Action.moveWindowToWorkspace) }),
        "focus": (1 ... 1, { word($0[0], or: ConfigError.Reason.invalidDirection).map(Action.focus) }),
        "fill": (1 ... 1, { word($0[0], or: ConfigError.Reason.invalidDirection).map(Action.fill) }),
        "move-window": (1 ... 2, {
            withPoints($0, or: ConfigError.Reason.invalidDirection) { .moveWindow(Step(direction: $0, points: $1)) }
        }),
        "resize": (1 ... 2, {
            withPoints($0, or: ConfigError.Reason.invalidResize) { .resize(Resize(change: $0, points: $1)) }
        }),
    ]

    /// `verb WORD [N]`: a word from `Word`'s cases, then the points, 15 when left out.
    private static func withPoints<Word: RawRepresentable>(
        _ arguments: [String],
        or reason: (String) -> ConfigError.Reason,
        _ make: (Word, CGFloat) -> Action
    ) -> Result<Action, ConfigError.Reason> where Word.RawValue == String {
        word(arguments[0], or: reason).flatMap { word in
            points(arguments.count == 2 ? arguments[1] : nil).map { make(word, $0) }
        }
    }

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

    private static func points(_ text: String?) -> Result<CGFloat, ConfigError.Reason> {
        guard let text else { return .success(defaultStep) }
        guard let points = Int(text), points >= 1 else { return .failure(.invalidStep(text)) }

        return .success(CGFloat(points))
    }
}
