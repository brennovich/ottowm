import CoreGraphics
import XCTest

final class DisplayLayoutsTests: XCTestCase {
    private let frame = CGRect(x: 100, y: 100, width: 800, height: 600)
    private let elsewhere = CGRect(x: 300, y: 200, width: 640, height: 480)
    private let layouts = DisplayLayouts()

    func testARecordOnAnotherDisplayLeavesTheFrameOnTheFirst() {
        layouts.record(frame, of: 100, on: Display.standard.id)

        layouts.record(elsewhere, of: 100, on: Display.external.id)

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
            let layouts = DisplayLayouts()
            layouts.record(frame, of: 100, on: Display.standard.id)

            layouts.record([testCase.outcome], on: Display.standard.id)

            XCTAssertEqual(layouts.frame(of: 100, on: Display.standard.id), testCase.expected, testCase.name)
        }
    }

    func testForgetDropsTheWindowFromEveryDisplay() {
        layouts.record(frame, of: 100, on: Display.standard.id)
        layouts.record(frame, of: 200, on: Display.standard.id)
        layouts.record(elsewhere, of: 100, on: Display.external.id)

        layouts.forget(100)

        XCTAssertNil(layouts.frame(of: 100, on: Display.standard.id))
        XCTAssertNil(layouts.frame(of: 100, on: Display.external.id))
        XCTAssertEqual(layouts.frame(of: 200, on: Display.standard.id), frame)
    }
}
