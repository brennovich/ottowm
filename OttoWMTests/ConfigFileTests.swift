import Foundation
import XCTest

final class ConfigFileTests: XCTestCase {
    private let bundle = Bundle(for: ConfigFileTests.self)

    private func load(userConfig: String?) -> Result<Config, ConfigError> {
        ConfigFile.load(bundle: bundle, environment: ["HOME": "/Users/otto"]) { url in
            url.path == "/Users/otto/.config/ottowm/ottowm"
                ? userConfig
                : try? String(contentsOf: url, encoding: .utf8)
        }
    }

    func testResolvesTheUserConfigPath() throws {
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
                ConfigFile.load(bundle: bundle, environment: testCase.environment) { url in
                    url.path == testCase.expected ? "hyper-1 = switch-to-workspace 1" : nil
                },
                .success(try makeConfig(["hyper-1": .switchToWorkspace(1)])),
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
        let config = try load(userConfig: nil).get()

        XCTAssertEqual(config.action(keyCode: 18, flags: .leftOption), .switchToWorkspace(1))
        XCTAssertEqual(
            config.action(keyCode: 12, flags: [.leftCommand, .leftControl, .leftOption, .leftShift]),
            .quit
        )
        XCTAssertEqual(
            config.action(keyCode: 15, flags: [.leftCommand, .leftControl, .leftOption, .leftShift]),
            .restart
        )
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

    func testBindsNothingWhenEvenTheBundledConfigIsUnavailable() {
        let cases: [(name: String, bundle: Bundle)] = [
            ("nothing bundled", Bundle(for: XCTestCase.self)),
            ("bundled file unreadable", bundle),
        ]

        for testCase in cases {
            XCTAssertEqual(
                ConfigFile.load(bundle: testCase.bundle, environment: ["HOME": "/Users/otto"]) { _ in nil },
                .success(Config([:])),
                testCase.name
            )
        }
    }
}
