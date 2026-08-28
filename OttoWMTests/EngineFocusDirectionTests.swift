import CoreGraphics
import XCTest

final class EngineFocusDirectionTests: EngineTestCase {
    private let center = CGRect(x: 400, y: 300, width: 200, height: 200)
    private let east = CGRect(x: 700, y: 300, width: 200, height: 200)

    func testParkedWindowIsIgnored() {
        let reference = create(StubWindow(id: 100, frame: center))
        let parked = create(StubWindow(id: 200, frame: east))
        let farther = create(StubWindow(id: 300, frame: CGRect(x: 1000, y: 300, width: 200, height: 200)))
        desktop.place(parked.id, at: .storage)
        focused = reference

        engine.focusWindow(.east)

        XCTAssertEqual(parked.focusCount, 0)
        XCTAssertEqual(farther.focusCount, 1)
    }

    func testWindowOfAnotherWorkspaceIsIgnored() {
        let reference = create(StubWindow(id: 100, frame: center))
        let elsewhere = create(StubWindow(id: 200, frame: east))
        moveFocusedWindow(elsewhere, to: 2)
        focused = reference

        engine.focusWindow(.east)

        XCTAssertEqual(elsewhere.focusCount, 0)
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

    func testWindowBehindTheReferenceIsFocused() {
        let reference = create(StubWindow(id: 100, frame: center))
        let behind = create(StubWindow(id: 200, frame: CGRect(x: 410, y: 310, width: 100, height: 100)))
        focused = reference

        engine.focusWindow(.west)

        XCTAssertEqual(behind.focusCount, 1)
    }

    func testNoWindowThatWayFocusesNothing() {
        let reference = create(StubWindow(id: 100, frame: center))
        let neighbor = create(StubWindow(id: 200, frame: east))
        focused = reference

        engine.focusWindow(.west)

        XCTAssertEqual(neighbor.focusCount, 0)
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

    func testHandleDispatchesTheFocusAction() {
        let reference = create(StubWindow(id: 100, frame: center))
        let neighbor = create(StubWindow(id: 200, frame: east))
        focused = reference

        engine.handle(.focus(.east))

        XCTAssertEqual(neighbor.focusCount, 1)
    }
}
