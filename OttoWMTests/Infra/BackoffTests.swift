import Foundation
import XCTest

final class BackoffTests: XCTestCase {
    private var scheduled: [(delay: TimeInterval, work: () -> Void)] = []

    private func makeBackoff(first: TimeInterval = 0.1, last: TimeInterval = 0.8) -> Backoff {
        Backoff(schedule: { self.scheduled.append(($0, $1)) }, first: first, last: last)
    }

    private func runScheduled(limit: Int = 10) -> [TimeInterval] {
        var delays: [TimeInterval] = []
        for _ in 0 ..< limit where !scheduled.isEmpty {
            let next = scheduled.removeFirst()
            delays.append(next.delay)
            next.work()
        }
        return delays
    }

    func testDoublesTheDelayUpToTheLastWhileTheAttemptIsNotDone() {
        var attempts = 0
        makeBackoff().run {
            attempts += 1
            return false
        }

        XCTAssertEqual(runScheduled(), [0.1, 0.2, 0.4, 0.8])
        XCTAssertEqual(attempts, 4)
    }

    func testStopsOnceTheAttemptIsDone() {
        var attempts = 0
        makeBackoff().run {
            attempts += 1
            return attempts == 2
        }

        XCTAssertEqual(runScheduled(), [0.1, 0.2])
    }

    func testSchedulesNothingWhenTheFirstDelayPassesTheLast() {
        makeBackoff(first: 1, last: 0.5).run { false }

        XCTAssertTrue(scheduled.isEmpty)
    }
}
