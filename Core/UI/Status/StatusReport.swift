/// Every value the About window shows, read at one moment.
struct StatusReport: Equatable {
    struct Setting: Equatable {
        let requirement: Requirement
        let value: Bool

        var isMet: Bool { value == requirement.expected }
    }

    let version: String
    let build: String
    let system: String
    let accessibilityGranted: Bool
    let hotkeysListening: Bool
    let secureInputHeld: Bool
    let workspace: Int
    let display: String
    let configPath: String
    let configExists: Bool
    let configError: ConfigError?
    let settings: [Setting]

    var configLine: String {
        configExists ? configPath : "bundled defaults, no file at \(configPath)"
    }

    /// The plain text put on the clipboard by Copy diagnostics.
    var text: String {
        var lines = [
            "OttoWM \(version) (\(build))",
            system,
            "",
            "Accessibility: \(accessibilityGranted ? "granted" : "not granted")",
            "Hotkeys: \(hotkeysListening ? "listening" : "not listening")",
            "Secure input: \(secureInputHeld ? "held by another app" : "free")",
            "Workspace: \(workspace) on \(display)",
            "",
            "Config: \(configLine)",
        ]
        if let configError {
            lines.append("Last reload: \(configError)")
        }
        lines.append("")
        lines += settings.map { setting in
            "\(setting.requirement.name): \(Self.state(setting.value)), expected \(Self.state(setting.requirement.expected))"
        }

        return lines.joined(separator: "\n")
    }

    private static func state(_ on: Bool) -> String { on ? "on" : "off" }
}
