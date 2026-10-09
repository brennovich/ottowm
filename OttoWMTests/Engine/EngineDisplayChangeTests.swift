import CoreGraphics
import XCTest

final class EngineDisplayChangeTests: EngineTestCase {
    func testADisplayChangeParksTheParkedWindowsAgainInOneBatch() {
        engine.start(windows: [])
        create(StubWindow(id: 100))
        moveFocusedWindow(create(StubWindow(id: 200)), to: 2)
        moveFocusedWindow(create(StubWindow(id: 300)), to: 2)
        desktop.clearCalls()
        let smaller = Display(
            id: Display.standard.id,
            fullFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 875)
        )
        desktop.display = smaller

        desktop.report(.displayChange(DisplayChange(from: .standard, to: smaller)))

        XCTAssertEqual(desktop.reframeBatches, [[200, 300]])
    }

    func testAScreenParametersChangeThatKeepsTheDisplayReparksTheParkedWindows() {
        engine.start(windows: [])
        create(StubWindow(id: 100))
        let parked = create(StubWindow(id: 200))
        moveFocusedWindow(parked, to: 2)

        desktop.report(.screenParametersChange)

        XCTAssertEqual(desktop.reparkedWindowIds, [[200]])
    }
}
