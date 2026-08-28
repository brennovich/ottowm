import CoreGraphics
import XCTest

final class WindowSystemTests: XCTestCase {
    private var reported: [OperationCost] = []
    private lazy var roundTrips = RoundTrips { [weak self] cost in self?.reported.append(cost) }

    private lazy var windowSystem = WindowSystem(
        focusedWindow: OperationCache { nil },
        onScreenWindows: OperationCache { [:] },
        window: { _ in nil },
        roundTrips: roundTrips
    )

    func testAnOperationIsPricedUnderItsName() {
        windowSystem.duringOperation("switch-to-workspace") {
            roundTrips.record(RoundTrip(kind: .read, subject: "AXPosition"), nanoseconds: 1000)
        }

        XCTAssertEqual(reported.map(\.operation), ["switch-to-workspace"])
    }

    func testTheOperationStillHoldsItsReadsForOneOperation() {
        var reads = 0
        let system = WindowSystem(
            focusedWindow: OperationCache { reads += 1; return nil },
            onScreenWindows: OperationCache { [:] },
            window: { _ in nil },
            roundTrips: roundTrips
        )

        system.duringOperation("switch-to-workspace") {
            _ = system.focused()
            _ = system.focused()
        }

        XCTAssertEqual(reads, 1)
    }
}
