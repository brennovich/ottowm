import CoreGraphics
import XCTest

final class EngineAdmissionTests: EngineTestCase {
    func testCreatedWindowIsAssignedToCurrentWorkspace() {
        engine.switchToWorkspace(2)
        create(StubWindow(id: 100))

        XCTAssertEqual(workspaces.workspace(for: 100), 2)
    }
}
