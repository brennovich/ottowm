import XCTest

final class RoundTripsTests: XCTestCase {
    private var reported: [OperationCost] = []
    private lazy var roundTrips = RoundTrips { [weak self] cost in self?.reported.append(cost) }

    private let position = RoundTrip(kind: .read, subject: "AXPosition")
    private let size = RoundTrip(kind: .write, subject: "AXSize")
    private let windowList = RoundTrip(kind: .read, subject: "CGWindowList")

    func testReportsTheRoundTripsAnOperationMade() {
        roundTrips.duringOperation("switch-to-workspace") {
            roundTrips.record(position, nanoseconds: 1000)
            roundTrips.record(size, nanoseconds: 3000)
        }

        XCTAssertEqual(reported.count, 1)
        XCTAssertEqual(reported.first?.operation, "switch-to-workspace")
        XCTAssertEqual(reported.first?.count, 2)
        XCTAssertEqual(reported.first?.roundTripNanoseconds, 4000)
    }

    func testTimesTheOperationItself() {
        roundTrips.duringOperation("switch-to-workspace") { roundTrips.record(position, nanoseconds: 1000) }

        XCTAssertGreaterThan(reported.first?.nanoseconds ?? 0, 0)
    }

    func testAggregatesRepeatedCallsToTheSameSubject() {
        roundTrips.duringOperation("switch-to-workspace") {
            roundTrips.record(position, nanoseconds: 1000)
            roundTrips.record(position, nanoseconds: 2000)
        }

        let call = reported.first?.calls.first
        XCTAssertEqual(call?.roundTrip, position)
        XCTAssertEqual(call?.count, 2)
        XCTAssertEqual(call?.nanoseconds, 3000)
    }

    func testOrdersTheMostExpensiveCallFirst() {
        roundTrips.duringOperation("switch-to-workspace") {
            roundTrips.record(position, nanoseconds: 1000)
            roundTrips.record(size, nanoseconds: 4000)
        }

        XCTAssertEqual(reported.first?.calls.map(\.roundTrip), [size, position])
    }

    func testReportsOnceForNestedOperations() {
        roundTrips.duringOperation("switch-to-workspace") {
            roundTrips.record(position, nanoseconds: 1000)
            roundTrips.duringOperation("restore-focus") { roundTrips.record(size, nanoseconds: 2000) }
        }

        XCTAssertEqual(reported.map(\.operation), ["switch-to-workspace"])
        XCTAssertEqual(reported.first?.count, 2)
    }

    func testEachOperationStartsFromZero() {
        roundTrips.duringOperation("move-window-to-workspace") { roundTrips.record(position, nanoseconds: 1000) }
        roundTrips.duringOperation("switch-to-workspace") { roundTrips.record(size, nanoseconds: 2000) }

        XCTAssertEqual(reported.map(\.count), [1, 1])
        XCTAssertEqual(reported.last?.calls.map(\.roundTrip), [size])
    }

    func testCallsOutsideAnOperationAreNotReported() {
        roundTrips.record(position, nanoseconds: 1000)

        XCTAssertTrue(reported.isEmpty)
    }

    func testAnOperationWithoutRoundTripsIsNotReported() {
        roundTrips.duringOperation("switch-to-workspace") {}

        XCTAssertTrue(reported.isEmpty)
    }

    func testMeasureRecordsTheCallAndReturnsTheValue() {
        let result = roundTrips.duringOperation("switch-to-workspace") {
            roundTrips.measure(.read, "AXRole") { 42 }
        }

        XCTAssertEqual(result, 42)
        XCTAssertEqual(reported.first?.calls.map(\.roundTrip), [RoundTrip(kind: .read, subject: "AXRole")])
    }

    func testRecordsCallsMadeFromSeveralThreadsAtOnce() {
        roundTrips.duringOperation("switch-to-workspace") {
            DispatchQueue.concurrentPerform(iterations: 8) { _ in
                for _ in 1...100 { roundTrips.record(position, nanoseconds: 1000) }
            }
        }

        XCTAssertEqual(reported.first?.calls.first?.count, 800)
        XCTAssertEqual(reported.first?.calls.first?.nanoseconds, 800_000)
    }

    func testAnOperationOnAnotherThreadDoesNotTakeOverTheOneInFlight() {
        let otherStarted = DispatchSemaphore(value: 0)
        let otherMayFinish = DispatchSemaphore(value: 0)
        let otherFinished = DispatchSemaphore(value: 0)

        roundTrips.duringOperation("switch-to-workspace") {
            DispatchQueue.global().async {
                self.roundTrips.duringOperation("focus-direction") {
                    otherStarted.signal()
                    otherMayFinish.wait()
                }
                otherFinished.signal()
            }
            otherStarted.wait()
            roundTrips.record(position, nanoseconds: 1000)
        }
        otherMayFinish.signal()
        otherFinished.wait()

        XCTAssertEqual(reported.map(\.operation), ["switch-to-workspace"])
        XCTAssertEqual(reported.first?.count, 1)
    }

    func testSummaryNamesTheOperationAndTheCallsItMade() {
        roundTrips.duringOperation("switch-to-workspace") {
            roundTrips.record(position, nanoseconds: 1_000_000)
            roundTrips.record(windowList, nanoseconds: 4_000_000)
        }

        let summary = reported.first?.summary ?? ""

        XCTAssertTrue(summary.hasPrefix("switch-to-workspace "), summary)
        XCTAssertTrue(summary.contains("2 round trips"), summary)
        XCTAssertTrue(summary.contains("read CGWindowList x1 4.00ms"), summary)
        XCTAssertTrue(summary.contains("read AXPosition x1 1.00ms"), summary)
    }
}
