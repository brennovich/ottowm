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

    func testAnOperationHoldsTheFocusedWindowAndTheOnScreenReads() {
        var focusedReads = 0
        var onScreenReads = 0
        let system = WindowSystem(
            focusedWindow: OperationCache { focusedReads += 1; return nil },
            onScreenWindows: OperationCache { onScreenReads += 1; return [:] },
            window: { _ in nil },
            roundTrips: roundTrips
        )

        system.duringOperation("switch-to-workspace") {
            _ = system.focused()
            _ = system.focused()
            _ = system.shows(100)
            _ = system.shows(100)
        }

        XCTAssertEqual(focusedReads, 1)
        XCTAssertEqual(onScreenReads, 1)
    }

    func testAScopedCopyReportsOnlyTheWindowsItOwns() {
        let owned = CGRect(x: 100, y: 100, width: 800, height: 600)
        let other = CGRect(x: 2000, y: 100, width: 800, height: 600)
        let system = WindowSystem(
            focusedWindow: OperationCache { StubWindow(id: 200, frame: other).snapshot() },
            onScreenWindows: OperationCache { [100: owned, 200: other] },
            window: { _ in nil },
            roundTrips: roundTrips
        ).scoped { $0.minX < 1792 }

        XCTAssertNil(system.focused())
        XCTAssertTrue(system.shows(100))
        XCTAssertFalse(system.shows(200))
        XCTAssertFalse(system.showsAny([200]))
        XCTAssertEqual(system.frames(of: [100, 200]), [100: owned])
    }

    func testReadsTheFramesOfTheWindowsInParallel() {
        let windows = (1 ... 8).map { StubWindow(id: CGWindowID($0) * 100, frame: CGRect(x: CGFloat($0), y: 0, width: 100, height: 100)) }
        let firstRead = DispatchSemaphore(value: 0)
        firstRead.signal()
        let anotherRead = DispatchSemaphore(value: 0)
        for window in windows {
            window.onReadFrame = {
                if firstRead.wait(timeout: .now()) == .success {
                    XCTAssertEqual(anotherRead.wait(timeout: .now() + 2), .success)
                } else {
                    anotherRead.signal()
                }
            }
        }
        let byId = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
        let system = WindowSystem(
            focusedWindow: OperationCache { nil },
            onScreenWindows: OperationCache { [:] },
            window: { byId[$0] },
            roundTrips: roundTrips
        )

        let frames = system.readFrames(of: windows.map(\.id) + [999])

        XCTAssertEqual(frames, Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0.frame) }))
    }
}
