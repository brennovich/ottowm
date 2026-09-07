import CoreGraphics
import XCTest

final class FilledWindowsTests: XCTestCase {
    private let original = CGRect(x: 100, y: 100, width: 800, height: 600)
    private let filled = CGRect(x: 15, y: 53, width: 1762, height: 1052)
    private var tabs: [CGWindowID: [CGWindowID]] = [:]
    private lazy var filledWindows = FilledWindows(tabs: { [weak self] in self?.tabs[$0] ?? [$0] })

    func testKnowsNoFrameForAWindowItNeverRecorded() {
        XCTAssertNil(filledWindows.restoringFrame(of: 100))
    }

    func testAFillKeepsTheFrameTheWindowCameFrom() {
        filledWindows.record([.filled(100, from: original)])

        XCTAssertEqual(filledWindows.restoringFrame(of: 100), original)
    }

    /// Filling again at another target must not record the frame the first fill gave the
    /// window, which would strand it there.
    func testASecondFillKeepsTheFrameFromBeforeTheFirst() {
        filledWindows.record([.filled(100, from: original)])
        filledWindows.record([.filled(100, from: filled)])

        XCTAssertEqual(filledWindows.restoringFrame(of: 100), original)
    }

    func testAnyOtherFrameChangeDropsTheFrame() {
        filledWindows.record([.filled(100, from: original)])
        filledWindows.record([.active(100)])

        XCTAssertNil(filledWindows.restoringFrame(of: 100))
    }

    func testRestoringOneTabEndsTheFillForTheWholeWindow() {
        tabs = [100: [100, 200], 200: [100, 200]]
        filledWindows.record([.filled(100, from: original)])

        filledWindows.record([.active(200)])

        XCTAssertNil(filledWindows.restoringFrame(of: 100))
    }

    /// The tab a fill went through can close while its siblings stay filled, so the frame
    /// cannot live with that tab alone.
    func testTheFrameOutlivesTheTabTheFillWentThrough() {
        tabs = [100: [100, 200], 200: [100, 200]]
        filledWindows.record([.filled(200, from: original)])

        tabs = [100: [100], 200: [200]]
        filledWindows.forget(200)

        XCTAssertEqual(filledWindows.restoringFrame(of: 100), original)
    }

    /// A tab opened while the window is filled outlives the tabs the fill recorded, so it
    /// takes the frame when it joins.
    func testATabThatJoinsAFilledWindowTakesItsFrame() {
        filledWindows.record([.filled(100, from: original)])

        tabs = [100: [100, 200], 200: [100, 200]]
        filledWindows.shareFrame(with: 200)

        tabs = [200: [200]]
        filledWindows.forget(100)

        XCTAssertEqual(filledWindows.restoringFrame(of: 200), original)
    }

    func testAWindowThatIsGoneKeepsItsFrameUntilItIsForgotten() {
        filledWindows.record([.filled(100, from: original)])
        filledWindows.record([.gone(100)])

        XCTAssertEqual(filledWindows.restoringFrame(of: 100), original)

        filledWindows.forget(100)

        XCTAssertNil(filledWindows.restoringFrame(of: 100))
    }
}
