import XCTest

final class TelemetryTests: XCTestCase {
    private var recorded: [(operation: String, ms: Double)] = []
    private var clockReadings: [TimeInterval] = []

    private func makeTelemetry() -> Telemetry {
        Telemetry(
            now: { [self] in clockReadings.isEmpty ? 0 : clockReadings.removeFirst() },
            record: { [self] operation, ms in recorded.append((operation, ms)) }
        )
    }

    func testSpanReturnsBodyResult() {
        let telemetry = makeTelemetry()

        let result = telemetry.span("operation") { 42 }

        XCTAssertEqual(result, 42)
    }

    func testSpanRunsVoidBodyAndRecordsOperationNameAndClockDeltaInMilliseconds() {
        clockReadings = [1.0, 1.0025]
        let telemetry = makeTelemetry()
        var bodyRan = false

        telemetry.span("saveWindowFocus") { bodyRan = true }

        XCTAssertTrue(bodyRan)
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded[0].operation, "saveWindowFocus")
        XCTAssertEqual(recorded[0].ms, 2.5, accuracy: 0.0001)
    }

    func testSpanRethrowsAndStillRecordsDuration() {
        clockReadings = [0, 0.001]
        let telemetry = makeTelemetry()

        XCTAssertThrowsError(
            try telemetry.span("operation") { throw TestError.boom }
        ) { error in
            XCTAssertEqual(error as? TestError, TestError.boom)
        }
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded[0].ms, 1.0, accuracy: 0.0001)
    }

    private enum TestError: Error {
        case boom
    }
}
