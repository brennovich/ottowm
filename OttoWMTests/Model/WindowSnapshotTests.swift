import CoreGraphics
import XCTest

final class WindowSnapshotTests: XCTestCase {
    func testAdmission() {
        let cases: [(name: String, snapshot: WindowSnapshot, isAdmissible: Bool)] = [
            ("a standard window, as Macs Fan Control reports", makeSnapshot(100), true),
            ("a window without an id", makeSnapshot(0), false),
            ("a full screen window", makeSnapshot(100, isFullScreen: true), false),
            ("a minimized window", makeSnapshot(100, isMinimized: true), false),
            ("a standard window stripped of its buttons, as Steam Helper reports",
             makeSnapshot(100, hasCloseButton: false, hasMinimizeButton: false), true),
            ("a dialog carrying the title bar buttons", makeSnapshot(100, isStandard: false), true),
            ("a dialog that can only be closed",
             makeSnapshot(100, isStandard: false, hasMinimizeButton: false), false),
            ("a panel with no buttons at all, as the Steam launcher process reports",
             makeSnapshot(100, isStandard: false, hasCloseButton: false, hasMinimizeButton: false), false),
        ]

        for testCase in cases {
            XCTAssertEqual(testCase.snapshot.isAdmissible, testCase.isAdmissible, testCase.name)
        }
    }
}
