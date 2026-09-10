import CoreGraphics
import XCTest

final class RestoringFramesTests: XCTestCase {
    private let original = CGRect(x: 100, y: 100, width: 800, height: 600)
    private let filled = CGRect(x: 15, y: 53, width: 1762, height: 1052)
    private var tabs: [CGWindowID: [CGWindowID]] = [:]
    private lazy var restoringFrames = RestoringFrames(tabs: { [weak self] in self?.tabs[$0] ?? [$0] })

    func testKnowsNoFrameForAWindowItNeverRecorded() {
        XCTAssertNil(restoringFrames.restoringFrame(of: 100))
    }

    func testAFillKeepsTheFrameTheWindowCameFrom() {
        restoringFrames.record([.filled(100, from: original)])

        XCTAssertEqual(restoringFrames.restoringFrame(of: 100), original)
    }

    /// Filling again at another target must not record the frame the first fill gave the
    /// window, which would strand it there.
    func testASecondFillKeepsTheFrameFromBeforeTheFirst() {
        restoringFrames.record([.filled(100, from: original)])
        restoringFrames.record([.filled(100, from: filled)])

        XCTAssertEqual(restoringFrames.restoringFrame(of: 100), original)
    }

    func testRelocateFitsEveryFrameIntoTheNewVisibleFrame() {
        let fit = Fit(from: Display.external.visibleFrame, into: Display.standard.visibleFrame)
        restoringFrames.record([.filled(100, from: original)])

        restoringFrames.relocate(with: fit)

        XCTAssertEqual(restoringFrames.restoringFrame(of: 100), fit.frame(original))
    }

    func testAnyOtherFrameChangeDropsTheFrame() {
        restoringFrames.record([.filled(100, from: original)])
        restoringFrames.record([.active(100)])

        XCTAssertNil(restoringFrames.restoringFrame(of: 100))
    }

    func testRestoringOneTabEndsTheFillForTheWholeWindow() {
        tabs = [100: [100, 200], 200: [100, 200]]
        restoringFrames.record([.filled(100, from: original)])

        restoringFrames.record([.active(200)])

        XCTAssertNil(restoringFrames.restoringFrame(of: 100))
    }

    /// The tab a fill went through can close while its siblings stay filled, so the frame
    /// cannot live with that tab alone.
    func testTheFrameOutlivesTheTabTheFillWentThrough() {
        tabs = [100: [100, 200], 200: [100, 200]]
        restoringFrames.record([.filled(200, from: original)])

        tabs = [100: [100], 200: [200]]
        restoringFrames.forget(200)

        XCTAssertEqual(restoringFrames.restoringFrame(of: 100), original)
    }

    /// A tab opened while the window is filled outlives the tabs the fill recorded, so it
    /// takes the frame when it joins.
    func testATabThatJoinsAFilledWindowTakesItsFrame() {
        restoringFrames.record([.filled(100, from: original)])

        tabs = [100: [100, 200], 200: [100, 200]]
        restoringFrames.shareFrame(with: 200)

        tabs = [200: [200]]
        restoringFrames.forget(100)

        XCTAssertEqual(restoringFrames.restoringFrame(of: 200), original)
    }

    func testAWindowThatIsGoneKeepsItsFrameUntilItIsForgotten() {
        restoringFrames.record([.filled(100, from: original)])
        restoringFrames.record([.gone(100)])

        XCTAssertEqual(restoringFrames.restoringFrame(of: 100), original)

        restoringFrames.forget(100)

        XCTAssertNil(restoringFrames.restoringFrame(of: 100))
    }
}
