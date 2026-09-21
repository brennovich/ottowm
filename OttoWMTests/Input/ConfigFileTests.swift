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

    func testReadsTheUserConfigUnderXDGConfigHome() throws {
        let config = ConfigFile.load(bundle: bundle, environment: ["HOME": "/Users/otto", "XDG_CONFIG_HOME": "~/cfg"]) { url in
            url.path == "/Users/otto/cfg/ottowm/ottowm" ? "hyper-1 = switch-to-workspace 1" : nil
        }

        XCTAssertEqual(config, .success(try makeConfig(["hyper-1": .action(.switchToWorkspace(1))])))
    }

    func testFallsBackToTheBundledConfigWhenThereIsNone() throws {
        let config = try load(userConfig: nil).get()

        XCTAssertEqual(config.binding(keyCode: 18, flags: .leftOption), .action(.switchToWorkspace(1)))
        XCTAssertEqual(
            config.binding(keyCode: 12, flags: [.leftCommand, .leftControl, .leftOption, .leftShift]),
            .quit
        )
        XCTAssertEqual(
            config.binding(keyCode: 15, flags: [.leftCommand, .leftControl, .leftOption, .leftShift]),
            .restart
        )
        XCTAssertEqual(
            config.binding(keyCode: 0, flags: [.leftCommand, .leftControl, .leftOption, .leftShift]),
            .about
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

    func testWriteDefaultsPutsTheBundledConfigAtTheUserPathCreatingItsDirectory() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: home) }

        ConfigFile.writeDefaults(bundle: bundle, environment: ["HOME": home.path])

        let bundled = try String(contentsOf: XCTUnwrap(bundle.url(forResource: "ottowm", withExtension: nil)), encoding: .utf8)
        XCTAssertEqual(try String(contentsOf: home.appendingPathComponent(".config/ottowm/ottowm"), encoding: .utf8), bundled)
    }

    func testWriteDefaultsWritesNothingWhenTheBundledConfigIsMissing() {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: home) }

        ConfigFile.writeDefaults(bundle: Bundle(for: XCTestCase.self), environment: ["HOME": home.path])

        XCTAssertFalse(FileManager.default.fileExists(atPath: home.path))
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
