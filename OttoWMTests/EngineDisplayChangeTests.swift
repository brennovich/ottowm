import CoreGraphics
import XCTest

final class EngineDisplayChangeTests: EngineTestCase {
    func testADisplayChangePlacesEveryManagedWindowInOneBatch() {
        engine.start(windows: [])
        create(StubWindow(id: 100))
        let parked = create(StubWindow(id: 200))
        moveFocusedWindow(parked, to: 2)
        desktop.clearCalls()
        desktop.display = .external

        desktop.handler?(.displayChange(from: .standard, to: .external))

        XCTAssertEqual(desktop.reframeBatches, [[100, 200]])
    }

    func testAScreenParametersChangeThatKeepsTheDisplayReparksTheParkedWindows() {
        engine.start(windows: [])
        create(StubWindow(id: 100))
        let parked = create(StubWindow(id: 200))
        moveFocusedWindow(parked, to: 2)

        desktop.handler?(.screenParametersChange)

        XCTAssertEqual(desktop.reparkedWindowIds, [[200]])
    }

    func testADisplayChangeBehindTheLockScreenWaitsForTheUnlock() {
        engine.start(windows: [])
        create(StubWindow(id: 100))
        desktop.clearCalls()
        screenIsLocked = true
        desktop.display = .external

        desktop.handler?(.displayChange(from: .standard, to: .external))

        XCTAssertEqual(desktop.reframeBatches, [])

        screenIsLocked = false
        engine.resync(windows: [])

        XCTAssertEqual(desktop.reframeBatches, [[100]])
    }

    func testTheUnlockPlacesTheWindowsFromTheDisplayFirstLeft() {
        let third = Display(
            id: DisplayID(rawValue: "third"),
            fullFrame: CGRect(x: 0, y: 0, width: 3008, height: 1692),
            visibleFrame: CGRect(x: 0, y: 25, width: 3008, height: 1667)
        )
        engine.start(windows: [])
        let win = create(StubWindow(id: 100))
        desktop.clearCalls()
        screenIsLocked = true
        desktop.handler?(.displayChange(from: .standard, to: .external))
        desktop.handler?(.displayChange(from: .external, to: third))
        desktop.display = third

        screenIsLocked = false
        engine.resync(windows: [])

        let fitted = Fit(from: Display.standard.visibleFrame, into: third.visibleFrame).frame(win.frame)
        XCTAssertEqual(desktop.reframeCalls.map(\.change), [.unpark(fitted)])
    }
}
