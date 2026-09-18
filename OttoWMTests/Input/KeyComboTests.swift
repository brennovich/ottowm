import CoreGraphics
import XCTest

final class KeyComboTests: XCTestCase {
    func testParsing() {
        let cases: [(text: String, keyCode: Int64, modifiers: [ModifierKey: ModifierSide])] = [
            ("1", 18, [:]),
            ("a", 0, [:]),
            ("f18", 79, [:]),
            ("alt-1", 18, [.option: .either]),
            ("lalt-1", 18, [.option: .left]),
            ("ralt-1", 18, [.option: .right]),
            ("lalt-shift-1", 18, [.option: .left, .shift: .either]),
            ("lshift-1", 18, [.shift: .left]),
            ("lctrl-rcmd-f18", 79, [.control: .left, .command: .right]),
            ("cmd-shift-a", 0, [.command: .either, .shift: .either]),
            ("hyper-1", 18, [.command: .either, .control: .either, .option: .either, .shift: .either]),
            ("LALT-1", 18, [.option: .left]),
        ]

        for testCase in cases {
            XCTAssertEqual(
                KeyCombo.parse(testCase.text),
                .success(KeyCombo(keyCode: testCase.keyCode, modifiers: testCase.modifiers)),
                testCase.text
            )
        }
    }

    func testParsingErrors() {
        let cases: [(text: String, expected: ConfigError.Reason)] = [
            ("", .missingKey("")),
            ("lalt-", .missingKey("lalt-")),
            ("meta-1", .unknownModifier("meta")),
            ("lalt-nope", .unknownKey("nope")),
            ("f21", .unknownKey("f21")),
            ("alt-lalt-1", .duplicateModifier("lalt")),
            ("hyper-cmd-1", .duplicateModifier("cmd")),
        ]

        for testCase in cases {
            XCTAssertEqual(KeyCombo.parse(testCase.text), .failure(testCase.expected), testCase.text)
        }
    }

    func testMatching() {
        let cases: [(text: String, flags: CGEventFlags, expected: Bool)] = [
            ("lalt-1", .leftOption, true),
            ("lalt-1", .rightOption, false),
            ("lalt-1", [.leftOption, .rightOption], false),
            ("lalt-1", .maskAlternate, false),
            ("lalt-1", [], false),
            ("lalt-1", [.leftOption, .leftCommand], false),
            ("lalt-1", [.leftOption, .leftControl], false),
            ("lalt-1", [.leftOption, .leftShift], false),
            ("ralt-1", .rightOption, true),
            ("ralt-1", .leftOption, false),
            ("alt-1", .leftOption, true),
            ("alt-1", .rightOption, true),
            ("alt-1", .maskAlternate, true),
            ("lalt-shift-1", [.leftOption, .leftShift], true),
            ("lalt-shift-1", .leftOption, false),
            ("cmd-1", .rightCommand, true),
            ("hyper-1", [.leftCommand, .leftControl, .leftOption, .leftShift], true),
            ("hyper-1", [.leftCommand, .leftControl, .leftOption], false),
        ]

        for testCase in cases {
            XCTAssertEqual(
                KeyCombo.parse(testCase.text).map { $0.matches(testCase.flags) },
                .success(testCase.expected),
                "\(testCase.text) against \(testCase.flags.rawValue)"
            )
        }
    }
}
