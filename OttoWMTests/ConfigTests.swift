import CoreGraphics
import XCTest

final class ConfigTests: XCTestCase {
    func testBinding() throws {
        let config = try makeConfig([
            "lalt-1": .action(.switchToWorkspace(1)),
            "lalt-shift-1": .action(.moveWindowToWorkspace(1)),
            "ralt-2": .action(.switchToWorkspace(2)),
        ])

        let cases: [(name: String, keyCode: Int64, flags: CGEventFlags, expected: Binding?)] = [
            ("bound key combo", 18, .leftOption, .action(.switchToWorkspace(1))),
            ("same key, different modifiers", 18, [.leftOption, .leftShift], .action(.moveWindowToWorkspace(1))),
            ("other bound key", 19, .rightOption, .action(.switchToWorkspace(2))),
            ("bound key, unmatched modifiers", 19, .leftOption, nil),
            ("unbound key", 20, .leftOption, nil),
        ]

        for testCase in cases {
            XCTAssertEqual(
                config.binding(keyCode: testCase.keyCode, flags: testCase.flags),
                testCase.expected,
                testCase.name
            )
        }
    }
}
