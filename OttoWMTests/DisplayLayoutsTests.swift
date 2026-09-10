import CoreGraphics
import XCTest

final class DisplayLayoutsTests: XCTestCase {
    private let frame = CGRect(x: 100, y: 100, width: 800, height: 600)
    private let elsewhere = CGRect(x: 300, y: 200, width: 640, height: 480)
    private var display = Display.standard.id
    private lazy var layouts = DisplayLayouts(display: { [weak self] in self?.display ?? Display.standard.id })

    func testRecordsTheFrameOnTheCurrentDisplayOnly() {
        layouts.record(frame, of: 100)

        XCTAssertEqual(layouts.frame(of: 100, on: Display.standard.id), frame)
        XCTAssertNil(layouts.frame(of: 100, on: Display.external.id))
    }

    func testARecordOnAnotherDisplayLeavesTheFrameOnTheFirst() {
        layouts.record(frame, of: 100)
        display = Display.external.id

        layouts.record(elsewhere, of: 100)

        XCTAssertEqual(layouts.frame(of: 100, on: Display.standard.id), frame)
        XCTAssertEqual(layouts.frame(of: 100, on: Display.external.id), elsewhere)
    }

    func testRecordKeepsTheFrameAParkReportsAndNothingElse() {
        let cases: [(name: String, outcome: FrameOutcome, expected: CGRect?)] = [
            ("parked", .parked(100, from: elsewhere), elsewhere),
            ("filled", .filled(100, from: elsewhere), frame),
            ("active", .active(100), frame),
            ("gone", .gone(100), frame),
        ]

        for testCase in cases {
            let layouts = DisplayLayouts(display: { Display.standard.id })
            layouts.record(frame, of: 100)

            layouts.record([testCase.outcome])

            XCTAssertEqual(layouts.frame(of: 100, on: Display.standard.id), testCase.expected, testCase.name)
        }
    }

    func testForgetDropsTheWindowFromEveryDisplay() {
        layouts.record(frame, of: 100)
        layouts.record(frame, of: 200)
        display = Display.external.id
        layouts.record(elsewhere, of: 100)

        layouts.forget(100)

        XCTAssertNil(layouts.frame(of: 100, on: Display.standard.id))
        XCTAssertNil(layouts.frame(of: 100, on: Display.external.id))
        XCTAssertEqual(layouts.frame(of: 200, on: Display.standard.id), frame)
    }
}
