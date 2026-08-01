import CoreGraphics
import XCTest

final class HotkeyBindingTests: XCTestCase {
    private let leftOption: CGEventFlags = [.maskAlternate, CGEventFlags(rawValue: 0x20)]
    private let rightOption: CGEventFlags = [.maskAlternate, CGEventFlags(rawValue: 0x40)]

    func testHotkeyAction() {
        let cases: [(name: String, keyCode: Int64, flags: CGEventFlags, expected: HotkeyAction?)] = [
            ("left option 1 switches", 18, leftOption, .switchToWorkspace(1)),
            ("left option 2 switches", 19, leftOption, .switchToWorkspace(2)),
            ("left option 3 switches", 20, leftOption, .switchToWorkspace(3)),
            ("left option 4 switches", 21, leftOption, .switchToWorkspace(4)),
            ("left option shift 1 moves", 18, leftOption.union(.maskShift), .moveWindowToWorkspace(1)),
            ("left option shift 4 moves", 21, leftOption.union(.maskShift), .moveWindowToWorkspace(4)),
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

    func testEventTapDecision() {
        let cases: [(name: String, type: CGEventType, keyCode: Int64, flags: CGEventFlags, expected: EventTapDecision)] = [
            ("tap disabled by timeout re-enables", .tapDisabledByTimeout, 18, leftOption, .reenableAndPass),
            ("tap disabled by user input re-enables", .tapDisabledByUserInput, 18, leftOption, .reenableAndPass),
            ("key down on switch hotkey consumes", .keyDown, 18, leftOption, .consume(.switchToWorkspace(1))),
            ("key down on move hotkey consumes", .keyDown, 19, leftOption.union(.maskShift), .consume(.moveWindowToWorkspace(2))),
            ("key down with right option passes", .keyDown, 18, rightOption, .pass),
            ("key down on unmapped key passes", .keyDown, 0, leftOption, .pass),
            ("key up on hotkey passes", .keyUp, 18, leftOption, .pass),
            ("flags changed passes", .flagsChanged, 18, leftOption, .pass),
        ]

        for testCase in cases {
            XCTAssertEqual(
                eventTapDecision(type: testCase.type, keyCode: testCase.keyCode, flags: testCase.flags),
                testCase.expected,
                testCase.name
            )
        }
    }
}
