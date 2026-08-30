import CoreGraphics

enum ModifierSide {
    case either, left, right
}

enum ModifierKey: CaseIterable {
    case command, control, option, shift

    fileprivate var mask: CGEventFlags {
        switch self {
        case .command: return .maskCommand
        case .control: return .maskControl
        case .option: return .maskAlternate
        case .shift: return .maskShift
        }
    }

    fileprivate var deviceBits: (left: UInt64, right: UInt64) {
        switch self {
        case .command: return (left: 0x8, right: 0x10)
        case .control: return (left: 0x1, right: 0x2000)
        case .option: return (left: 0x20, right: 0x40)
        case .shift: return (left: 0x2, right: 0x4)
        }
    }
}

struct KeyCombo: Hashable {
    let keyCode: Int64
    let modifiers: [ModifierKey: ModifierSide]

    static func parse(_ text: String) -> Result<KeyCombo, ConfigError.Reason> {
        var components = text.lowercased()
            .split(separator: "-", omittingEmptySubsequences: false)
            .map(String.init)

        guard let key = components.popLast(), !key.isEmpty else {
            return .failure(.missingKey(text))
        }
        guard let keyCode = Self.keyCodesByName[key] else {
            return .failure(.unknownKey(key))
        }

        var modifiers: [ModifierKey: ModifierSide] = [:]
        for name in components {
            switch Self.modifiers(named: name) {
            case let .failure(reason):
                return .failure(reason)
            case let .success(named):
                guard named.allSatisfy({ modifiers.updateValue($0.1, forKey: $0.0) == nil }) else {
                    return .failure(.duplicateModifier(name))
                }
            }
        }

        return .success(KeyCombo(keyCode: keyCode, modifiers: modifiers))
    }

    func matches(_ flags: CGEventFlags) -> Bool {
        ModifierKey.allCases.allSatisfy { key in
            guard let side = modifiers[key] else { return !flags.contains(key.mask) }
            guard flags.contains(key.mask) else { return false }

            switch side {
            case .either: return true
            case .left: return flags.rawValue & key.deviceBits.left != 0 && flags.rawValue & key.deviceBits.right == 0
            case .right: return flags.rawValue & key.deviceBits.right != 0 && flags.rawValue & key.deviceBits.left == 0
            }
        }
    }

    private static let modifierKeysByName: [String: ModifierKey] = [
        "cmd": .command, "command": .command,
        "ctrl": .control, "control": .control,
        "alt": .option, "opt": .option, "option": .option,
        "shift": .shift,
    ]

    private static let sidesByPrefix: [Character: ModifierSide] = ["l": .left, "r": .right]

    private static func modifiers(named name: String) -> Result<[(ModifierKey, ModifierSide)], ConfigError.Reason> {
        if name == "hyper" {
            return .success(ModifierKey.allCases.map { ($0, .either) })
        }
        if let key = modifierKeysByName[name] {
            return .success([(key, .either)])
        }

        guard let side = name.first.flatMap({ sidesByPrefix[$0] }),
              let key = modifierKeysByName[String(name.dropFirst())]
        else { return .failure(.unknownModifier(name)) }

        return .success([(key, side)])
    }

    private static let keyCodesByName: [String: Int64] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29,
        "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40,
        "n": 45, "m": 46,

        "equal": 24, "minus": 27, "rightbracket": 30, "leftbracket": 33, "quote": 39,
        "semicolon": 41, "backslash": 42, "comma": 43, "slash": 44, "period": 47, "backtick": 50,

        "return": 36, "tab": 48, "space": 49, "delete": 51, "escape": 53, "forwarddelete": 117,
        "home": 115, "pageup": 116, "end": 119, "pagedown": 121,
        "left": 123, "right": 124, "down": 125, "up": 126,

        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
        "f9": 101, "f10": 109, "f11": 103, "f12": 111, "f13": 105, "f14": 107, "f15": 113,
        "f16": 106, "f17": 64, "f18": 79, "f19": 80, "f20": 90,
    ]
}
