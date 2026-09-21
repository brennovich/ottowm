import XCTest

final class StatusReportTests: XCTestCase {
    private func makeReport(
        configExists: Bool = true,
        configError: ConfigError? = nil,
        secureInputHeld: Bool = false
    ) -> StatusReport {
        StatusReport(
            version: "0.0.14",
            build: "1287",
            system: "macOS 26.6.2 · Apple Silicon",
            accessibilityGranted: true,
            hotkeysListening: false,
            secureInputHeld: secureInputHeld,
            workspace: 2,
            display: "2560×1440",
            configPath: "~/.config/ottowm/ottowm",
            configExists: configExists,
            configError: configError,
            settings: [
                StatusReport.Setting(requirement: Requirements.all[0], value: true),
                StatusReport.Setting(requirement: Requirements.all[2], value: true),
            ]
        )
    }

    func testASettingIsMetWhenItsValueIsTheExpectedOne() {
        let requirement = Requirements.all[2]

        XCTAssertTrue(StatusReport.Setting(requirement: requirement, value: requirement.expected).isMet)
        XCTAssertFalse(StatusReport.Setting(requirement: requirement, value: !requirement.expected).isMet)
    }

    func testTheTextListsEveryRowWithItsState() {
        XCTAssertEqual(makeReport(secureInputHeld: true).text, """
        OttoWM 0.0.14 (1287)
        macOS 26.6.2 · Apple Silicon

        Accessibility: granted
        Hotkeys: not listening
        Secure input: held by another app
        Workspace: 2 on 2560×1440

        Config: ~/.config/ottowm/ottowm

        Group windows by application: on, expected on
        Automatically rearrange Spaces based on most recent use: on, expected off
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
