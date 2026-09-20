import XCTest

final class PagerTabViewTests: XCTestCase {
    private let bounds = CGRect(origin: .zero, size: TabShape.size)
    private let view = PagerTabView(number: .stub())

    func testRetractSqueezesTheShapeAgainstTheRightEdgeAndMovesTheBadgeOut() {
        view.retract()

        XCTAssertEqual(view.shapeLayer.frame, CGRect(x: bounds.maxX - 20, y: 0, width: 20, height: bounds.height))
        XCTAssertGreaterThanOrEqual(view.badgeLayer.frame.minX, bounds.maxX)
        XCTAssertTrue(view.isRetracted)
    }

    func testRestoreReturnsTheShapeAndTheBadgeToTheirFullFrames() {
        view.retract()

        view.restore()

        XCTAssertEqual(view.shapeLayer.frame, bounds)
        XCTAssertEqual(view.badgeLayer.frame, PagerTabView.badge)
        XCTAssertFalse(view.isRetracted)
    }

    func testTheNumberRollsOnlyWhileTheTabIsRevealed() {
        let cases: [(name: String, prepare: (PagerTabView) -> Void, rolling: [[String]])] = [
            ("revealed", { $0.reveal() }, [[RollingNumber.animationKey], [RollingNumber.animationKey]]),
            ("never revealed", { _ in }, []),
            ("concealed after a reveal", { $0.reveal(); $0.conceal {} }, []),
        ]

        for testCase in cases {
            let number = RollingNumber.stub()
            let view = PagerTabView(number: number)
            withExtendedLifetime(NSWindow.offscreen(hosting: view)) {
                testCase.prepare(view)

                view.show(workspace: 2)
            }

            XCTAssertEqual(number.rolling, testCase.rolling, testCase.name)
            XCTAssertEqual(number.shownValue, "2", testCase.name)
        }
    }
}
