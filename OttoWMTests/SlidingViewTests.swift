import XCTest

final class SlidingViewTests: XCTestCase {
    func testTheRevealedContentFillsTheView() {
        let content = CALayer()
        let view = SlidingView(content: content, size: CGSize(width: 16, height: 16), hiddenOffset: CGSize(width: 16, height: -16))

        view.reveal()

        XCTAssertEqual(content.frame, view.bounds)
    }
}
