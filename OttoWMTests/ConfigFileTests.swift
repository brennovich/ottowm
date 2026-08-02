import Foundation
import XCTest

final class ConfigFileTests: XCTestCase {
    private let bundle = Bundle(for: ConfigFileTests.self)

    private func load(
        userConfig: String?,
        environment: [String: String] = ["HOME": "/Users/otto"]
    ) -> Result<Config, ConfigError> {
        let userPath = ConfigFile.userPath(environment: environment)

        return ConfigFile.load(bundle: bundle, environment: environment) { url in
            url == userPath ? userConfig : try? String(contentsOf: url, encoding: .utf8)
        }
    }

    private func bundledConfig() throws -> Config {
        try makeConfig([
            "lopt-1": .switchToWorkspace(1),
            "lopt-2": .switchToWorkspace(2),
            "lopt-3": .switchToWorkspace(3),
            "lopt-4": .switchToWorkspace(4),
            "lopt-shift-1": .moveWindowToWorkspace(1),
            "lopt-shift-2": .moveWindowToWorkspace(2),
            "lopt-shift-3": .moveWindowToWorkspace(3),
            "lopt-shift-4": .moveWindowToWorkspace(4),
        ])
    }

    func testUserPath() {
        let cases: [(name: String, environment: [String: String], expected: String)] = [
            (
                "defaults to ~/.config",
                ["HOME": "/Users/otto"],
                "/Users/otto/.config/ottowm/ottowm"
            ),
            (
                "honours XDG_CONFIG_HOME",
                ["HOME": "/Users/otto", "XDG_CONFIG_HOME": "/Users/otto/cfg"],
                "/Users/otto/cfg/ottowm/ottowm"
            ),
            (
                "OTTOWM_CONFIG wins",
                ["HOME": "/Users/otto", "XDG_CONFIG_HOME": "/Users/otto/cfg", "OTTOWM_CONFIG": "/tmp/otto"],
                "/tmp/otto"
            ),
            (
                "OTTOWM_CONFIG expands a tilde",
                ["HOME": "/Users/otto", "OTTOWM_CONFIG": "~/otto"],
                "/Users/otto/otto"
            ),
            (
                "XDG_CONFIG_HOME expands a tilde",
                ["HOME": "/Users/otto", "XDG_CONFIG_HOME": "~/cfg"],
                "/Users/otto/cfg/ottowm/ottowm"
            ),
            (
                "empty variables are ignored",
                ["HOME": "/Users/otto", "XDG_CONFIG_HOME": "", "OTTOWM_CONFIG": ""],
                "/Users/otto/.config/ottowm/ottowm"
            ),
        ]

        for testCase in cases {
            XCTAssertEqual(
                ConfigFile.userPath(environment: testCase.environment).path,
                testCase.expected,
                testCase.name
            )
        }
    }

    func testUserConfigReplacesTheBundledOne() throws {
        XCTAssertEqual(
            load(userConfig: "hyper-1 = switch-to-workspace 1"),
            .success(try makeConfig(["hyper-1": .switchToWorkspace(1)]))
        )
    }

    func testFallsBackToTheBundledConfigWhenThereIsNone() throws {
        XCTAssertEqual(load(userConfig: nil), .success(try bundledConfig()))
    }

    func testRejectsAnUnparseableUserConfig() {
        XCTAssertEqual(
            load(userConfig: "lalt-1 = warp 1"),
            .failure(ConfigError(line: 1, reason: .unknownAction("warp")))
        )
    }

    func testEmptyUserConfigBindsNothing() {
        XCTAssertEqual(load(userConfig: ""), .success(Config([:])))
    }

    func testBindsNothingWhenEvenTheBundledConfigIsUnusable() {
        let environment = ["HOME": "/Users/otto"]
        let userPath = ConfigFile.userPath(environment: environment)

        let cases: [(name: String, bundle: Bundle, bundledConfig: String?)] = [
            ("nothing bundled", Bundle(for: XCTestCase.self), nil),
            ("bundled file unreadable", bundle, nil),
            ("bundled file unparseable", bundle, "lalt-1 = warp 1"),
        ]

        for testCase in cases {
            XCTAssertEqual(
                ConfigFile.load(bundle: testCase.bundle, environment: environment) { url in
                    url == userPath ? nil : testCase.bundledConfig
                },
                .success(Config([:])),
                testCase.name
            )
        }
    }
}
