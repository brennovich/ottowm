import CoreGraphics
import XCTest

final class EngineFocusDirectionTests: EngineTestCase {
    private let center = CGRect(x: 400, y: 300, width: 200, height: 200)
    private let east = CGRect(x: 700, y: 300, width: 200, height: 200)

    func testParkedWindowIsIgnored() {
        let reference = create(StubWindow(id: 100, frame: center))
        let parked = create(StubWindow(id: 200, frame: east))
        let farther = create(StubWindow(id: 300, frame: CGRect(x: 1000, y: 300, width: 200, height: 200)))
        parkedWindows.park(parked.id, owing: east)
        focused = reference

        engine.focusWindow(.east)

        XCTAssertEqual(parked.focusCount, 0)
        XCTAssertEqual(farther.focusCount, 1)
    }

    func testWindowMissingFromTheScreenIsIgnored() {
        let reference = create(StubWindow(id: 100, frame: center))
        let backgroundTab = create(StubWindow(id: 200, frame: east))
        let farther = create(StubWindow(id: 300, frame: CGRect(x: 1000, y: 300, width: 200, height: 200)))
        offScreenWindowIds = [backgroundTab.id]
        focused = reference

        engine.focusWindow(.east)

        XCTAssertEqual(backgroundTab.focusCount, 0)
        XCTAssertEqual(farther.focusCount, 1)
    }

    func testReferenceOutsideTheCurrentWorkspaceFocusesNothing() {
        let neighbor = create(StubWindow(id: 200, frame: east))
        let unmanaged = add(StubWindow(id: 900, frame: center))

        for reference in [nil, unmanaged] {
            focused = reference

            engine.focusWindow(.east)

            XCTAssertEqual(neighbor.focusCount, 0)
        }
    }

    func testCandidateFramesAreReadWithoutWindowSnapshots() {
        let reference = create(StubWindow(id: 100, frame: center))
        let neighbor = create(StubWindow(id: 200, frame: east))
        focused = reference
        let readsBefore = neighbor.snapshotReadCount

        engine.focusWindow(.east)

        XCTAssertEqual(neighbor.snapshotReadCount, readsBefore)
        XCTAssertEqual(neighbor.focusCount, 1)
    }
}
