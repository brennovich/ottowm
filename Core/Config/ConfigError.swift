struct ConfigError: Error, Equatable, CustomStringConvertible {
    let line: Int
    let reason: Reason

    var description: String { "line \(line): \(reason)" }

    enum Reason: Error, Equatable, CustomStringConvertible {
        case syntax(String)
        case unknownModifier(String)
        case duplicateModifier(String)
        case missingKey(String)
        case unknownKey(String)
        case unknownAction(String)
        case malformedAction(String)
        case invalidWorkspace(String)
        case invalidDirection(String)

        var description: String {
            switch self {
            case let .syntax(line): return "expected `key combo = action`, got \(line)"
            case let .unknownModifier(name): return "unknown modifier \(name)"
            case let .duplicateModifier(name): return "modifier \(name) is already part of the combo"
            case let .missingKey(combo): return "\(combo) names no key"
            case let .unknownKey(name): return "unknown key \(name)"
            case let .unknownAction(name): return "unknown action \(name)"
            case let .malformedAction(action): return "expected `<action>` or `<action> <argument>`, got \(action)"
            case let .invalidWorkspace(value): return "workspace must be a number from 1, got \(value)"
            case let .invalidDirection(value):
                return "direction must be one of \(Direction.allCases.map(\.rawValue).joined(separator: ", ")), got \(value)"
            }
        }
    }
}
