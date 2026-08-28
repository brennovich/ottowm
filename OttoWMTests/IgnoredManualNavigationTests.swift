import XCTest

final class IgnoredManualNavigationTests: XCTestCase {
    private enum Step {
        case record
        case take
    }

    func testOneShotConsumption() {
        let cases: [(name: String, steps: [Step], takes: Bool)] = [
            ("nothing recorded", [], false),
            ("a recorded navigation", [.record], true),
            ("a record already consumed", [.record, .take], false),
            ("a take without a record leaves nothing armed", [.take], false),
            ("a record made after a take", [.take, .record], true),
            ("a record made twice is still consumed once", [.record, .record, .take], false),
        ]

        for testCase in cases {
            var ignored = IgnoredManualNavigation()
            for step in testCase.steps {
                switch step {
                case .record: ignored.record()
                case .take: _ = ignored.take()
                }
            }

            XCTAssertEqual(ignored.take(), testCase.takes, testCase.name)
        }
    }
}
