import CoreGraphics
import XCTest

final class MaximizedWindowsTests: XCTestCase {
    private let original = CGRect(x: 100, y: 100, width: 800, height: 600)
    private let filled = CGRect(x: 15, y: 53, width: 1762, height: 1052)
    private let maximized = MaximizedWindows()

    func testKnowsNoFrameForAWindowItNeverRecorded() {
        XCTAssertNil(maximized.restoringFrame(of: 100))
    }

    func testAMaximizeKeepsTheFrameTheWindowCameFrom() {
        maximized.record([.maximized(100, from: original)])

        XCTAssertEqual(maximized.restoringFrame(of: 100), original)
    }

    /// Maximizing again at a different inset must not record the filled frame as the one to
    /// go back to, which would strand the window a hair short of the screen.
    func testASecondMaximizeKeepsTheFrameFromBeforeTheFirst() {
        maximized.record([.maximized(100, from: original)])
        maximized.record([.maximized(100, from: filled)])

        XCTAssertEqual(maximized.restoringFrame(of: 100), original)
    }

    func testAnyOtherFrameChangeDropsTheFrame() {
        maximized.record([.maximized(100, from: original)])
        maximized.record([.active(100)])

        XCTAssertNil(maximized.restoringFrame(of: 100))
    }

    func testAWindowThatIsGoneKeepsItsFrameUntilItIsForgotten() {
        maximized.record([.maximized(100, from: original)])
        maximized.record([.gone(100)])

        XCTAssertEqual(maximized.restoringFrame(of: 100), original)

        maximized.forget(100)

        XCTAssertNil(maximized.restoringFrame(of: 100))
    }
}
