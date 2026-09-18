import XCTest

final class TabAreaTests: XCTestCase {
    func testFrameIsTheBottomRightCornerOfTheDisplay() {
        let display = Display(
            id: DisplayID(rawValue: "external"),
            fullFrame: CGRect(x: 1792, y: -120, width: 2560, height: 1440),
            visibleFrame: CGRect(x: 1792, y: -95, width: 2560, height: 1415)
        )

        XCTAssertEqual(TabArea(display: display).frame, CGRect(x: 4298, y: 1262, width: 54, height: 58))
    }

    func testIsOverlapped() {
        let cases: [(name: String, frames: [CGWindowID: CGRect], expected: Bool)] = [
            ("window over the tab", [1: CGRect(x: 1000, y: 500, width: 800, height: 600)], true),
            ("window ending at the tab's left edge", [1: CGRect(x: 938, y: 500, width: 800, height: 600)], false),
            ("parked window", [1: CGRect(x: 1791, y: 1119, width: 800, height: 600)], false),
            ("full screen transition window", [1: Display.standard.fullFrame], false),
        ]

        for testCase in cases {
            XCTAssertEqual(TabArea(display: .standard).isOverlapped(by: testCase.frames), testCase.expected, testCase.name)
        }
    }
}
