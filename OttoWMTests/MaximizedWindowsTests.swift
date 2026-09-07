import CoreGraphics
import XCTest

final class MaximizedWindowsTests: XCTestCase {
    private let original = CGRect(x: 100, y: 100, width: 800, height: 600)
    private var tabs: [CGWindowID: [CGWindowID]] = [:]
    private lazy var maximized = MaximizedWindows(tabs: { [weak self] in self?.tabs[$0] ?? [$0] })

    func testKnowsNoFrameForAWindowItNeverRecorded() {
        XCTAssertNil(maximized.restoringFrame(of: 100))
    }

    func testAMaximizeKeepsTheFrameTheWindowCameFrom() {
        maximized.record([.maximized(100, from: original)])

        XCTAssertEqual(maximized.restoringFrame(of: 100), original)
    }

    func testAnyOtherFrameChangeDropsTheFrame() {
        maximized.record([.maximized(100, from: original)])
        maximized.record([.active(100)])

        XCTAssertNil(maximized.restoringFrame(of: 100))
    }

    /// Tabs of one window share the frame the maximize took them from: a tab opened after
    /// it lands at the filled frame with them.
    func testATabOfAMaximizedWindowGoesBackToTheSameFrame() {
        tabs = [100: [100, 200], 200: [100, 200]]
        maximized.record([.maximized(100, from: original)])

        XCTAssertEqual(maximized.restoringFrame(of: 200), original)
    }

    func testRestoringOneTabEndsTheMaximizeForTheWholeWindow() {
        tabs = [100: [100, 200], 200: [100, 200]]
        maximized.record([.maximized(100, from: original)])

        maximized.record([.active(200)])

        XCTAssertNil(maximized.restoringFrame(of: 100))
    }

    /// The tab a maximize went through can close while its siblings stay maximized, so the
    /// frame cannot live with that tab alone.
    func testTheFrameOutlivesTheTabTheMaximizeWentThrough() {
        tabs = [100: [100, 200], 200: [100, 200]]
        maximized.record([.maximized(200, from: original)])

        tabs = [100: [100], 200: [200]]
        maximized.forget(200)

        XCTAssertEqual(maximized.restoringFrame(of: 100), original)
    }

    /// A tab opened while the window is maximized outlives the tabs the maximize recorded,
    /// so it takes the frame when it joins.
    func testATabThatJoinsAMaximizedWindowTakesItsFrame() {
        maximized.record([.maximized(100, from: original)])

        tabs = [100: [100, 200], 200: [100, 200]]
        maximized.shareFrame(with: 200)

        tabs = [200: [200]]
        maximized.forget(100)

        XCTAssertEqual(maximized.restoringFrame(of: 200), original)
    }

    func testAWindowThatIsGoneKeepsItsFrameUntilItIsForgotten() {
        maximized.record([.maximized(100, from: original)])
        maximized.record([.gone(100)])

        XCTAssertEqual(maximized.restoringFrame(of: 100), original)

        maximized.forget(100)

        XCTAssertNil(maximized.restoringFrame(of: 100))
    }
}
