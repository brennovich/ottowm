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
    let display: String
    let configPath: String
    let configExists: Bool
    let configError: ConfigError?
    let settings: [Setting]

    var configLine: String {
        configExists ? configPath : "bundled defaults, no file at \(configPath)"
    }

    /// The `defaults write` lines of the settings that are not set as OttoWM needs them.
    /// One `killall Dock` closes the block: the Dock has to read the writes once, not once per line.
    var fixes: String {
        let commands = settings.filter { !$0.isMet }.map(\.requirement.fixCommand)

        return commands.isEmpty ? "" : (commands + ["killall Dock"]).joined(separator: "\n")
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
            "Display: \(display)",
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
