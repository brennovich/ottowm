import CoreGraphics
import XCTest

final class EngineActionTests: EngineTestCase {
    private let frame = CGRect(x: 400, y: 300, width: 200, height: 200)
    private let east = CGRect(x: 700, y: 300, width: 200, height: 200)

    @discardableResult
    private func focus(_ id: CGWindowID) -> StubWindow {
        let win = create(StubWindow(id: id, frame: frame))
        focused = win
        desktop.clearCalls()
        return win
    }

    func testUnassignedFocusedWindowIsEnrolledFirst() {
        let win = add(StubWindow(id: 900, frame: frame))
        focused = win

        engine.handle(.moveWindow(.east))

        XCTAssertEqual(workspaces.workspace(for: 900), 1)
        XCTAssertEqual(desktop.reframeCalls.map(\.windowId), [900, 900])
        XCTAssertEqual(desktop.reframeCalls.map(\.change), [.unpark(nil), .move(.east)])
    }

    func testNothingHappensWhenNoWindowOfTheCurrentWorkspaceIsFocused() {
        focused = nil

        engine.handle(.moveWindow(.east))

        XCTAssertTrue(desktop.reframeCalls.isEmpty)
    }

    func testAMaximizedWindowIsNeitherMovedNorResized() {
        focused = create(StubWindow(id: 100, frame: frame))
        desktop.maximizedFrame = frame
        desktop.clearCalls()

        for action in [Action.moveWindow(.east), .resize(.wider)] {
            engine.handle(action)
        }

        XCTAssertTrue(desktop.reframeCalls.isEmpty)
    }

    func testParkedWindowOfTheCurrentWorkspaceIsLeftAlone() {
        let win = create(StubWindow(id: 100, frame: frame))
        focused = win
        parkedWindows.park(win.id, from: frame)
        desktop.clearCalls()

        engine.handle(.moveWindow(.east))

        XCTAssertTrue(desktop.reframeCalls.isEmpty)
    }

    func testReframingReadsNoTabCountWhenNoWindowOfTheAppStandsWhereTheFocusedOneDoes() {
        let win = create(StubWindow(id: 100, appName: "Terminal", frame: frame))
        create(StubWindow(id: 200, appName: "Terminal", frame: CGRect(x: 0, y: 0, width: 200, height: 200)))
        focused = win
        let before = windows.values.reduce(0) { $0 + $1.tabCountReadCount }

        engine.handle(.moveWindow(.east))

        XCTAssertEqual(windows.values.reduce(0) { $0 + $1.tabCountReadCount }, before)
    }

    func testATabOpenedWhileMaximizedKeepsTheFrameOnceTheOthersClose() {
        let win = focus(100)
        engine.handle(.maximize)
        let tab = create(StubWindow(id: 101, frame: frame, tabCount: 2))

        engine.handle(.destroyed(win.id))
        focused = tab
        desktop.clearCalls()
        engine.handle(.maximize)

        XCTAssertEqual(desktop.reframeCalls.map(\.change), [.maximize(restoring: frame)])
    }

    /// Parking and unparking report `.active`, which is what tells `OriginalFrames` the
    /// window left the filled frame. Only the reframe path feeds it, so a trip to another
    /// workspace and back does not.
    func testAWindowThatVisitedAnotherWorkspaceCanStillBePutBack() {
        let win = focus(100)
        engine.handle(.maximize)

        moveFocusedWindow(win, to: 2)
        engine.switchToWorkspace(2)
        focused = win
        desktop.clearCalls()

        engine.handle(.maximize)

        XCTAssertEqual(desktop.reframeCalls.map(\.change), [.maximize(restoring: frame)])
    }

    func testParkedWindowIsIgnored() {
        let reference = create(StubWindow(id: 100, frame: frame))
        let parked = create(StubWindow(id: 200, frame: east))
        let farther = create(StubWindow(id: 300, frame: CGRect(x: 1000, y: 300, width: 200, height: 200)))
        parkedWindows.park(parked.id, from: east)
        focused = reference

        engine.focusWindow(.east)

        XCTAssertEqual(parked.focusCount, 0)
        XCTAssertEqual(farther.focusCount, 1)
    }

    func testFocusingByDirectionRefreshesWhereTheCandidatesStand() {
        let reference = create(StubWindow(id: 100, frame: frame))
        let neighbor = create(StubWindow(id: 200, frame: east))
        let moved = east.offsetBy(dx: 50, dy: 0)
        neighbor.moveTo(moved)
        focused = reference

        engine.focusWindow(.east)

        XCTAssertEqual(layouts.frame(of: 200, on: Display.standard.id), moved)
    }

    func testWindowMissingFromTheScreenIsIgnored() {
        let reference = create(StubWindow(id: 100, frame: frame))
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
        let elsewhere = create(StubWindow(id: 900, frame: frame))
        moveFocusedWindow(elsewhere, to: 2)
        let focusCount = neighbor.focusCount

        for reference in [nil, elsewhere] {
            focused = reference

            engine.focusWindow(.east)

            XCTAssertEqual(neighbor.focusCount, focusCount)
        }
    }

    func testCandidateFramesAreReadWithoutWindowSnapshots() {
        let reference = create(StubWindow(id: 100, frame: frame))
        let neighbor = create(StubWindow(id: 200, frame: east))
        focused = reference
        let readsBefore = neighbor.snapshotReadCount

        engine.focusWindow(.east)

        XCTAssertEqual(neighbor.snapshotReadCount, readsBefore)
        XCTAssertEqual(neighbor.focusCount, 1)
    }

    func testMoveFocusedWindowAwayHandsFocusToAWindowLeftBehind() {
        let win1 = create(StubWindow(id: 100))
        let win2 = create(StubWindow(id: 200))

        moveFocusedWindow(win2, to: 2)

        XCTAssertEqual(win1.focusCount, 1)
        XCTAssertEqual(win2.focusCount, 0)
    }

    func testMoveWindowToWorkspaceIgnoresAnInvalidTargetOrNoFocusedWindow() {
        focused = nil
        engine.moveFocusedWindow(toWorkspace: 2)

        focused = add(StubWindow(id: 100))
        engine.moveFocusedWindow(toWorkspace: 0)

        XCTAssertTrue(desktop.reframeCalls.isEmpty)
        XCTAssertEqual(workspaces.allWindowIds, [])
    }
}
