import Foundation

/// One macOS setting OttoWM depends on. `name` is the README's row, shortened to what the About window fits.
/// A key absent from its domain holds `absentValue`, the macOS default.
struct Requirement: Equatable {
    let name: String
    let domain: String
    let key: String
    let expected: Bool
    let absentValue: Bool

    var fixCommand: String { "defaults write \(domain) \(key) -bool \(expected)" }

    func value(read: (String, String) -> Bool?) -> Bool {
        read(domain, key) ?? absentValue
    }
}

enum Requirements {
    static let all = [
        Requirement(
            name: "Group windows by app",
            domain: "com.apple.dock",
            key: "expose-group-apps",
            expected: true,
            absentValue: false
        ),
        Requirement(
            name: "Separate Spaces per display",
            domain: "com.apple.spaces",
            key: "spans-displays",
            expected: false,
            absentValue: false
        ),
        Requirement(
            name: "Rearrange Spaces by use",
            domain: "com.apple.dock",
            key: "mru-spaces",
            expected: false,
            absentValue: true
        ),
        Requirement(
            name: "Hide and show the Dock",
            domain: "com.apple.dock",
            key: "autohide",
            expected: true,
            absentValue: false
        ),
    ]

    /// `defaults write -int 1` is common, so the value is read as a number rather than a Bool.
    static func read(domain: String, key: String) -> Bool? {
        (CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? NSNumber)?.boolValue
    }
}
