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
        lopt-q = quit
        lopt-r = restart
        lopt-h = focus west
        lopt-shift-h = move-window west
        lopt-shift-l = move-window east 100
        """

        XCTAssertEqual(
            ConfigFileParser.parse(text),
            .success(try makeConfig([
                "lalt-1": .switchToWorkspace(1),
                "lalt-shift-1": .moveWindowToWorkspace(1),
                "hyper-f18": .switchToWorkspace(12),
                "lopt-q": .quit,
                "lopt-r": .restart,
                "lopt-h": .focus(.west),
                "lopt-shift-h": .moveWindow(Step(direction: .west, points: 15)),
                "lopt-shift-l": .moveWindow(Step(direction: .east, points: 100)),
            ]))
        )
    }

    func testParsesNoBindings() {
        for text in ["", "\n   \n"] {
            XCTAssertEqual(ConfigFileParser.parse(text), .success(Config([:])), text.debugDescription)
        }
    }

    func testLineErrors() {
        assertErrors([
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
                "the first problem stops the parse",
                "lalt-2 = warp-to-workspace 2\nmeta-1 = switch-to-workspace 1",
                ConfigError(line: 1, reason: .unknownAction("warp-to-workspace"))
            ),
        ])
    }

    func testActionErrors() {
        assertErrors([
            (
                "an action that does not parse",
                "lalt-1 = warp-to-workspace 1",
                ConfigError(line: 1, reason: .unknownAction("warp-to-workspace"))
            ),
            (
                "an unknown action without an argument",
                "lalt-1 = warp",
                ConfigError(line: 1, reason: .unknownAction("warp"))
            ),
            (
                "an action that takes no argument, given one",
                "lalt-1 = quit 1",
                ConfigError(line: 1, reason: .malformedAction("quit 1"))
            ),
            (
                "an action that takes a workspace, given none",
                "lalt-1 = switch-to-workspace",
                ConfigError(line: 1, reason: .malformedAction("switch-to-workspace"))
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
                "an action that takes a direction, given none",
                "lalt-1 = focus",
                ConfigError(line: 1, reason: .malformedAction("focus"))
            ),
            (
                "an action with an invalid direction",
                "lalt-1 = focus sideways",
                ConfigError(line: 1, reason: .invalidDirection("sideways"))
            ),
        ])
    }

    func testStepActionErrors() {
        assertErrors([
            (
                "an action that takes a direction and a step, given none",
                "lalt-1 = move-window",
                ConfigError(line: 1, reason: .malformedAction("move-window"))
            ),
            (
                "an action that takes a direction and a step, given a third argument",
                "lalt-1 = move-window east 15 fast",
                ConfigError(line: 1, reason: .malformedAction("move-window east 15 fast"))
            ),
            (
                "a step action with an invalid direction",
                "lalt-1 = move-window sideways",
                ConfigError(line: 1, reason: .invalidDirection("sideways"))
            ),
            (
                "a step action with a step that is not a number",
                "lalt-1 = move-window east abc",
                ConfigError(line: 1, reason: .invalidStep("abc"))
            ),
            (
                "a step action with a step below one point",
                "lalt-1 = move-window east 0",
                ConfigError(line: 1, reason: .invalidStep("0"))
            ),
        ])
    }

    private func assertErrors(
        _ cases: [(name: String, text: String, expected: ConfigError)],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for testCase in cases {
            XCTAssertEqual(
                ConfigFileParser.parse(testCase.text),
                .failure(testCase.expected),
                testCase.name,
                file: file,
                line: line
            )
        }
    }
}
