import XCTest

final class SlidingViewTests: XCTestCase {
    private let duration: TimeInterval = 0.2
    private let hiddenOffset = CGSize(width: 50, height: -50)
    private let content = CALayer()
    private let size = CGSize(width: 16, height: 16)
    private lazy var view = SlidingView(content: content, size: size, hiddenOffset: hiddenOffset, duration: duration)
    private lazy var window = NSWindow.offscreen(hosting: view)

    override func setUp() {
        super.setUp()
        _ = window
    }

    private var hidden: CATransform3D {
        CATransform3DMakeTranslation(hiddenOffset.width, hiddenOffset.height, 0)
    }

    private var slideStart: CATransform3D? {
        (content.animation(forKey: SlidingView.animationKey) as? CABasicAnimation)?.fromValue as? CATransform3D
    }

    private func advance(to time: TimeInterval) {
        CATransaction.flush()
        content.timeOffset = time
        CATransaction.flush()
    }

    func testTheContentStartsHidden() {
        XCTAssertTrue(CATransform3DEqualToTransform(content.transform, hidden))
        XCTAssertFalse(view.isRevealed)
    }

    func testRevealSlidesTheContentFromHiddenIntoPlace() throws {
        view.reveal()

        XCTAssertEqual(content.frame, CGRect(origin: .zero, size: size))
        XCTAssertTrue(CATransform3DEqualToTransform(try XCTUnwrap(slideStart), hidden))
        XCTAssertTrue(view.isRevealed)
    }

    func testConcealSlidesTheContentToHiddenAndReportsTheEnd() {
        view.reveal()
        let ended = expectation(description: "conceal ended")

        view.conceal { ended.fulfill() }

        XCTAssertTrue(CATransform3DEqualToTransform(content.transform, hidden))
        XCTAssertFalse(view.isRevealed)
        wait(for: [ended], timeout: 1)
    }

    func testARevealDuringAConcealStartsFromWhereTheContentIs() throws {
        content.speed = 0
        view.reveal()
        advance(to: duration * 1.5)
        view.conceal {}
        advance(to: duration * 2)

        view.reveal()

        let start = try XCTUnwrap(slideStart)
        XCTAssertGreaterThan(start.m41, 0)
        XCTAssertLessThan(start.m41, hidden.m41)
    }
}
