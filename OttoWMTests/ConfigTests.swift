import CoreGraphics
import XCTest

final class ConfigTests: XCTestCase {
    func testAction() throws {
        let config = try makeConfig([
            "lalt-1": .switchToWorkspace(1),
            "lalt-shift-1": .moveWindowToWorkspace(1),
            "ralt-2": .switchToWorkspace(2),
        ])

        let cases: [(name: String, keyCode: Int64, flags: CGEventFlags, expected: Action?)] = [
            ("bound key combo", 18, .leftOption, .switchToWorkspace(1)),
            ("same key, different modifiers", 18, [.leftOption, .leftShift], .moveWindowToWorkspace(1)),
            ("other bound key", 19, .rightOption, .switchToWorkspace(2)),
            ("bound key, unmatched modifiers", 19, .leftOption, nil),
            ("unbound key", 20, .leftOption, nil),
        ]

        for testCase in cases {
            XCTAssertEqual(
                config.action(keyCode: testCase.keyCode, flags: testCase.flags),
                testCase.expected,
                testCase.name
            )
        }
    }
}
