import XCTest

final class PagerTabViewTests: XCTestCase {
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
