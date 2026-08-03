import XCTest

final class ConfigFileParserTests: XCTestCase {
    func testParsesBindings() throws {
        let text = """
        # With a comment
          # And another comment
        lopt-1 = switch-to-workspace 3  # side comment
        lalt-1 = switch-to-workspace 2
        lalt-1 = switch-to-workspace 1

        lalt-shift-1 = move-window-to-workspace 1
          hyper-f18   =   switch-to-workspace 12
        """

        XCTAssertEqual(
            ConfigFileParser.parse(text),
            .success(try makeConfig([
                "lalt-1": .switchToWorkspace(1),
                "lalt-shift-1": .moveWindowToWorkspace(1),
                "hyper-f18": .switchToWorkspace(12),
            ]))
        )
    }

    func testParsesNoBindings() {
        for text in ["", "\n   \n"] {
            XCTAssertEqual(ConfigFileParser.parse(text), .success(Config([:])), text.debugDescription)
        }
    }

    func testErrors() {
        let cases: [(name: String, text: String, expected: ConfigError)] = [
            (
                "line without an assignment",
                "lalt-1 switch-to-workspace 1",
                ConfigError(line: 1, reason: .syntax("lalt-1 switch-to-workspace 1"))
            ),
            (
                "assignment without a key combo",
                "= switch-to-workspace 1",
                ConfigError(line: 1, reason: .syntax("= switch-to-workspace 1"))
            ),
            (
                "a combo that does not parse, reported against its line",
                "lalt-1 = switch-to-workspace 1\n\nlalt-nope = switch-to-workspace 2",
                ConfigError(line: 3, reason: .unknownKey("nope"))
            ),
            (
                "an action that does not parse",
                "lalt-1 = warp-to-workspace 1",
                ConfigError(line: 1, reason: .unknownAction("warp-to-workspace"))
            ),
            (
                "assignment without an action",
                "lalt-1 =",
                ConfigError(line: 1, reason: .malformedAction(""))
            ),
            (
                "an action with an invalid workspace",
                "lalt-1 = switch-to-workspace 0",
                ConfigError(line: 1, reason: .invalidWorkspace("0"))
            ),
            (
                "the first problem stops the parse",
                "lalt-2 = warp-to-workspace 2\nmeta-1 = switch-to-workspace 1",
                ConfigError(line: 1, reason: .unknownAction("warp-to-workspace"))
            ),
        ]

        for testCase in cases {
            XCTAssertEqual(
                ConfigFileParser.parse(testCase.text),
                .failure(testCase.expected),
                testCase.name
            )
        }
    }
}
