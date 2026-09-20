import XCTest

final class CueViewTests: XCTestCase {
    private let view = CueView()
    private lazy var window = NSWindow.offscreen(hosting: view)
    private let full = CGRect(
        x: CueView.size.width - TabShape.size.width,
        y: CueView.size.height - TabShape.size.height,
        width: TabShape.size.width,
        height: TabShape.size.height
    )

    override func setUp() {
        super.setUp()
        _ = window
    }

    private var pulse: CAAnimation? {
        view.ring.animation(forKey: CueView.pulseKey)
    }

    private func keyframes(_ keyPath: String) throws -> CAKeyframeAnimation {
        let group = try XCTUnwrap(pulse as? CAAnimationGroup)
        let animations = try XCTUnwrap(group.animations as? [CAKeyframeAnimation])

        return try XCTUnwrap(animations.first { $0.keyPath == keyPath })
    }

    private func scales() throws -> [Double] {
        try XCTUnwrap(keyframes("transform").values as? [NSValue]).map { $0.caTransform3DValue.m11 }
    }

    private func numbers(_ keyPath: String) throws -> [Double] {
        try XCTUnwrap(keyframes(keyPath).values as? [NSNumber]).map(\.doubleValue)
    }

    func testTheRingPulsesWhileTheCueIsOnScreenAndStopsOnceItHasSlidOut() {
        view.reveal()
        XCTAssertNotNil(pulse)
        let out = expectation(description: "the cue has slid out")

        view.conceal { out.fulfill() }

        wait(for: [out], timeout: 1)
        XCTAssertNil(pulse)
    }

    func testARevealThatInterruptsTheSlideOutLeavesTheRunningPulseAlone() throws {
        view.reveal()
        let running = try XCTUnwrap(pulse)
        let interrupted = expectation(description: "the conceal has finished")
        view.conceal { interrupted.fulfill() }

        view.reveal()

        wait(for: [interrupted], timeout: 1)
        XCTAssertIdentical(pulse, running)
    }

    func testThePulseRunsForAsLongAsTheFlagStaysSet() throws {
        view.reveal()

        XCTAssertEqual(try XCTUnwrap(pulse).repeatCount, .infinity)
    }

    func testARingRisesFromUnderTheTabAndIsFullyDrawnWhereItLeavesTheOutline() throws {
        view.reveal()

        let scales = try scales()
        XCTAssertLessThan(scales[0], 1)
        XCTAssertEqual(scales[1], 1)
        XCTAssertGreaterThan(scales[2], 1)
        XCTAssertEqual(try numbers("opacity"), [0, 1, 0])
        XCTAssertLessThan(try XCTUnwrap(keyframes("transform").keyTimes?[1]).doubleValue, 0.5)
    }

    func testTheStrokeKeepsItsWidthOnScreenWhileTheRingGrows() throws {
        view.reveal()

        let drawn = zip(try numbers("lineWidth"), try scales()).map(*)

        for width in drawn.dropFirst() {
            XCTAssertEqual(width, drawn[0], accuracy: 0.0001)
        }
    }

    func testRetractSqueezesTheRingsAgainstTheRightEdge() {
        view.retract()

        XCTAssertEqual(view.rings.frame, CGRect(x: full.maxX - 20, y: full.minY, width: 20, height: full.height))
        XCTAssertTrue(view.isRetracted)
    }

    func testRestoreReturnsTheRingsToTheTabsFrame() {
        view.retract()

        view.restore()

        XCTAssertEqual(view.rings.frame, full)
        XCTAssertFalse(view.isRetracted)
    }
}
