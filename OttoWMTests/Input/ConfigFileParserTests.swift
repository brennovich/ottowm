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
        lopt-a = about
        lopt-h = focus west
        lopt-shift-h = move-window west
        lopt-ctrl-c = center-window
        lopt-m = maximize
        lopt-ctrl-h = tile west
        lopt-ctrl-shift-l = resize wider
        """

        XCTAssertEqual(
            ConfigFileParser.parse(text),
            .success(try makeConfig([
                "lalt-1": .action(.switchToWorkspace(1)),
                "lalt-shift-1": .action(.moveWindowToWorkspace(1)),
                "hyper-f18": .action(.switchToWorkspace(12)),
                "lopt-q": .quit,
                "lopt-r": .restart,
                "lopt-a": .about,
                "lopt-h": .action(.focus(.west)),
                "lopt-shift-h": .action(.moveWindow(.west)),
                "lopt-ctrl-c": .action(.centerWindow),
                "lopt-m": .action(.maximize),
                "lopt-ctrl-h": .action(.tile(.west)),
                "lopt-ctrl-shift-l": .action(.resize(.wider)),
            ]))
        )
    }

    func testParsesNoBindings() {
        for text in ["", "\n   \n"] {
            XCTAssertEqual(ConfigFileParser.parse(text), .success(Config([:])), text.debugDescription)
        }
    }

    func testParsesThePagerSetting() throws {
        let cases: [(name: String, text: String, showsPager: Bool)] = [
            ("shown without a pager line", "lopt-q = quit", true),
            ("hidden by pager = off", "pager = off", false),
            ("the last pager line wins", "pager = off\npager = on", true),
        ]

        for testCase in cases {
            XCTAssertEqual(try ConfigFileParser.parse(testCase.text).get().showsPager, testCase.showsPager, testCase.name)
        }
    }

    func testParsesTheSpacingSetting() throws {
        let cases: [(name: String, text: String, spacing: CGFloat)] = [
            ("15 without a spacing line", "lopt-q = quit", 15),
            ("set by spacing = 30", "spacing = 30", 30),
            ("the last spacing line wins", "spacing = 30\nspacing = 40", 40),
        ]

        for testCase in cases {
            XCTAssertEqual(try ConfigFileParser.parse(testCase.text).get().spacing, testCase.spacing, testCase.name)
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
            (
                "a pager setting that is neither on nor off",
                "lopt-q = quit\npager = maybe",
                ConfigError(line: 2, reason: .invalidPager("maybe"))
            ),
            (
                "a spacing that is not a number",
                "spacing = abc",
                ConfigError(line: 1, reason: .invalidSpacing("abc"))
            ),
            (
                "a spacing below one point",
                "spacing = 0",
                ConfigError(line: 1, reason: .invalidSpacing("0"))
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
                "an action with an invalid direction",
                "lalt-1 = focus sideways",
                ConfigError(line: 1, reason: .invalidDirection("sideways"))
            ),
            (
                "a move with an invalid direction",
                "lalt-1 = move-window sideways",
                ConfigError(line: 1, reason: .invalidDirection("sideways"))
            ),
            (
                "a resize with an unknown change",
                "lalt-1 = resize sideways",
                ConfigError(line: 1, reason: .invalidResize("sideways"))
            ),
        ])
    }

    func testMoveAndResizeTakeNoAmount() {
        assertErrors([
            (
                "a move given an amount",
                "lalt-1 = move-window east 15",
                ConfigError(line: 1, reason: .malformedAction("move-window east 15"))
            ),
            (
                "a resize given an amount",
                "lalt-1 = resize wider 15",
                ConfigError(line: 1, reason: .malformedAction("resize wider 15"))
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
