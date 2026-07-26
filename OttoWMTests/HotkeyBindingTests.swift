import CoreGraphics
import XCTest

final class HotkeyBindingTests: XCTestCase {
    private let leftOption: CGEventFlags = [.maskAlternate, CGEventFlags(rawValue: 0x20)]
    private let rightOption: CGEventFlags = [.maskAlternate, CGEventFlags(rawValue: 0x40)]

    func testHotkeyAction() {
        let cases: [(name: String, keyCode: Int64, flags: CGEventFlags, expected: HotkeyAction?)] = [
            ("left option 1 switches", 18, leftOption, .switchToVirtualSpace(1)),
            ("left option 2 switches", 19, leftOption, .switchToVirtualSpace(2)),
            ("left option 3 switches", 20, leftOption, .switchToVirtualSpace(3)),
            ("left option 4 switches", 21, leftOption, .switchToVirtualSpace(4)),
            ("left option shift 1 moves", 18, leftOption.union(.maskShift), .moveWindowToVirtualSpace(1)),
            ("left option shift 4 moves", 21, leftOption.union(.maskShift), .moveWindowToVirtualSpace(4)),
            ("right option passes through", 18, rightOption, nil),
            ("both options pass through", 18, leftOption.union(rightOption), nil),
            ("option without a device bit passes through", 18, .maskAlternate, nil),
            ("no modifiers passes through", 18, [], nil),
            ("command disqualifies", 18, leftOption.union(.maskCommand), nil),
            ("control disqualifies", 18, leftOption.union(.maskControl), nil),
            ("non-digit key passes through", 0, leftOption, nil),
            ("digit outside 1-4 passes through", 23, leftOption, nil),
        ]

        for testCase in cases {
            XCTAssertEqual(
                hotkeyAction(keyCode: testCase.keyCode, flags: testCase.flags),
                testCase.expected,
                testCase.name
            )
        }
    }
}
