import XCTest

final class StatusReportTests: XCTestCase {
    private func makeReport(
        configExists: Bool = true,
        configError: ConfigError? = nil,
        secureInputHeld: Bool = false,
        values: [Bool] = [true, true]
    ) -> StatusReport {
        StatusReport(
            version: "0.0.14",
            build: "1287",
            system: "macOS 26.6.2 · Apple Silicon",
            accessibilityGranted: true,
            hotkeysListening: false,
            secureInputHeld: secureInputHeld,
            display: "2560×1440",
            configPath: "~/.config/ottowm/ottowm",
            configExists: configExists,
            configError: configError,
            settings: [
                StatusReport.Setting(requirement: Requirements.all[0], value: values[0]),
                StatusReport.Setting(requirement: Requirements.all[2], value: values[1]),
            ]
        )
    }

    func testASettingIsMetWhenItsValueIsTheExpectedOne() {
        let requirement = Requirements.all[2]

        XCTAssertTrue(StatusReport.Setting(requirement: requirement, value: requirement.expected).isMet)
        XCTAssertFalse(StatusReport.Setting(requirement: requirement, value: !requirement.expected).isMet)
    }

    func testTheFixesAreTheWriteLinesOfTheSettingsThatAreNotMetAndOneDockRestart() {
        XCTAssertEqual(makeReport(values: [false, true]).fixes, """
        defaults write com.apple.dock expose-group-apps -bool true
        defaults write com.apple.dock mru-spaces -bool false
        killall Dock
        """)
    }

    func testThereAreNoFixesWhenEverySettingIsMet() {
        XCTAssertEqual(makeReport(values: [true, false]).fixes, "")
    }

    func testTheTextListsEveryRowWithItsState() {
        XCTAssertEqual(makeReport(secureInputHeld: true).text, """
        OttoWM 0.0.14 (1287)
        macOS 26.6.2 · Apple Silicon

        Accessibility: granted
        Hotkeys: not listening
        Secure input: held by another app
        Display: 2560×1440

        Config: ~/.config/ottowm/ottowm

        Group windows by app: on, expected on
        Rearrange Spaces by use: on, expected off
        """)
    }

    func testTheConfigLineNamesTheBundledDefaultsWhenThereIsNoFile() {
        XCTAssertTrue(makeReport(configExists: false).text.contains(
            "Config: bundled defaults, no file at ~/.config/ottowm/ottowm"
        ))
    }

    func testTheLastReloadErrorFollowsTheConfigLine() {
        let report = makeReport(configError: ConfigError(line: 3, reason: .unknownAction("warp")))

        XCTAssertTrue(report.text.contains("Config: ~/.config/ottowm/ottowm\nLast reload: line 3: unknown action warp\n"))
    }
}
