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
}
