import XCTest

extension RollingNumber {
    static func stub(duration: TimeInterval = 0.05) -> RollingNumber {
        RollingNumber(value: 1, size: CGSize(width: 20, height: 18), font: .systemFont(ofSize: 12), color: .black, duration: duration)
    }

    var shownValue: String? {
        texts.first { $0.opacity == 1 }?.string as? String
    }

    var entryOffset: CGFloat? {
        let entering = texts.first { $0.opacity == 1 }
        let roll = entering?.animation(forKey: RollingNumber.animationKey) as? CAAnimationGroup
        let move = roll?.animations?.first { ($0 as? CABasicAnimation)?.keyPath == "transform" } as? CABasicAnimation
        return (move?.fromValue as? CATransform3D)?.m42
    }

    var rolling: [[String]] {
        texts.compactMap { $0.animationKeys() }
    }

    private var texts: [CATextLayer] {
        (layer.sublayers ?? []).compactMap { $0 as? CATextLayer }
    }
}

final class RollingNumberTests: XCTestCase {
    private let number = RollingNumber.stub()
    private lazy var window = NSWindow.offscreen(hosting: number.layer)

    override func setUp() {
        super.setUp()
        _ = window
    }

    func testTheNewValueEntersFromAboveOnlyWhenItIncreases() {
        let cases: [(name: String, from: Int, to: Int, entryOffset: CGFloat)] = [
            ("higher", 2, 3, -RollingNumber.distance),
            ("lower", 3, 2, RollingNumber.distance),
        ]

        for testCase in cases {
            number.set(testCase.from)

            number.roll(to: testCase.to)

            XCTAssertEqual(number.entryOffset, testCase.entryOffset, testCase.name)
        }
    }

    func testTheInitialValueIsShown() {
        XCTAssertEqual(number.shownValue, "1")
    }

    func testSetShowsTheValueWithoutRolling() {
        number.set(2)

        XCTAssertEqual(number.shownValue, "2")
        XCTAssertEqual(number.rolling, [])
    }

    func testRollShowsTheValueAndRollsBothNumbers() {
        number.roll(to: 2)

        XCTAssertEqual(number.shownValue, "2")
        XCTAssertEqual(number.rolling, [[RollingNumber.animationKey], [RollingNumber.animationKey]])
    }

    func testARollInsideAnOpenTransactionAddsOnlyTheRoll() {
        CATransaction.flush()
        number.layer.opacity = 0.5

        number.roll(to: 2)
        CATransaction.flush()

        XCTAssertEqual(number.rolling, [[RollingNumber.animationKey], [RollingNumber.animationKey]])
    }
}
