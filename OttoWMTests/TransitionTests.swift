import XCTest

final class TransitionTests: XCTestCase {
    private let duration: TimeInterval = 0.2
    private let hidden = CATransform3DMakeTranslation(50, -50, 0)
    private let layer = CALayer()
    private lazy var window = NSWindow.offscreen(hosting: layer)
    private lazy var transition = Transition(layer: layer, hidden: hidden, duration: duration)

    override func setUp() {
        super.setUp()
        _ = window
    }

    private var transitionStart: CATransform3D? {
        (layer.animation(forKey: Transition.animationKey) as? CABasicAnimation)?.fromValue as? CATransform3D
    }

    private func advance(to time: TimeInterval) {
        CATransaction.flush()
        layer.timeOffset = time
        CATransaction.flush()
    }

    func testTheLayerStartsHidden() {
        _ = transition

        XCTAssertTrue(CATransform3DEqualToTransform(layer.transform, hidden))
    }

    func testShowMovesTheLayerFromHiddenToShown() throws {
        transition.show()

        XCTAssertTrue(CATransform3DIsIdentity(layer.transform))
        XCTAssertTrue(CATransform3DEqualToTransform(try XCTUnwrap(transitionStart), hidden))
    }

    func testHideMovesTheLayerToHiddenAndReportsTheEnd() {
        transition.show()
        let ended = expectation(description: "hide ended")

        transition.hide { ended.fulfill() }

        XCTAssertTrue(CATransform3DEqualToTransform(layer.transform, hidden))
        wait(for: [ended], timeout: 1)
    }

    func testAShowDuringAHideStartsFromWhereTheLayerIs() throws {
        layer.speed = 0
        transition.show()
        advance(to: duration * 1.5)
        transition.hide {}
        advance(to: duration * 2)

        transition.show()

        let start = try XCTUnwrap(transitionStart)
        XCTAssertGreaterThan(start.m41, 0)
        XCTAssertLessThan(start.m41, hidden.m41)
    }
}
