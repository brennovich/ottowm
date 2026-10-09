import CoreGraphics
import XCTest

final class WindowPlacementAbsorbTests: EngineTestCase {
    private let onRight = CGRect(x: 2000, y: 100, width: 800, height: 600)
    private let parkedFrom = CGRect(x: 2100, y: 150, width: 640, height: 480)
    private let fit = DisplayChange(from: .right, to: .standard).fit

    private func stateOfTheRightEngine(original: [CGWindowID: CGRect] = [:]) -> SavedState {
        let active = add(StubWindow(id: 200, frame: onRight))
        let parked = add(StubWindow(id: 300, frame: hiddenEdgeFrame(size: parkedFrom.size, on: .right)))
        layouts.record(active.frame, of: 200, on: Display.right.id)
        layouts.record(parkedFrom, of: 300, on: Display.right.id)
        return savedState(current: 2, [(active, 2), (parked, 1)], parked: [300: parkedFrom], original: original, on: .right)
    }

    func testAbsorbedWindowsJoinTheWorkspaceOfTheirNumberAndArePlacedByTheCurrentOne() {
        placement.assign(add(StubWindow(id: 100)).snapshot(), to: 1)

        placement.absorb(stateOfTheRightEngine())

        XCTAssertEqual(workspaces.windowIds(in: 1), [100, 300])
        XCTAssertEqual(Set(placement.parked.keys), [200])
    }

    func testAbsorbingRelocatesOnlyTheAbsorbedWindows() {
        placement.assign(add(StubWindow(id: 100)).snapshot(), to: 1)
        layouts.record(onRight, of: 100, on: Display.right.id)
        desktop.clearCalls()

        placement.absorb(stateOfTheRightEngine())

        XCTAssertEqual(Set(desktop.reframeCalls.map(\.windowId)), [200, 300])
    }

    func testAbsorbingWindowsPlacedByTheirOwnCurrentWorkspaceMovesEachOnce() {
        placement.absorb(stateOfTheRightEngine())

        XCTAssertEqual(desktop.reframeCalls.map(\.change), [.unpark(fit.frame(onRight)), .park(from: fit.frame(parkedFrom))])
    }

    func testAbsorbingFitsOnlyTheAbsorbedFramesARestoreGoesBackTo() {
        let own = CGRect(x: 300, y: 200, width: 640, height: 480)
        placement.assign(add(StubWindow(id: 100)).snapshot(), to: 1)
        originalFrames.record([.filled(100, from: own)])

        placement.absorb(stateOfTheRightEngine(original: [200: onRight]))

        XCTAssertEqual(originalFrames.originalFrame(of: 100), own)
        XCTAssertEqual(originalFrames.originalFrame(of: 200), fit.frame(onRight))
    }

    func testAWindowBothEnginesHoldKeepsItsPlaceInTheAbsorbingEngine() {
        placement.assign(add(StubWindow(id: 300)).snapshot(), to: 1)

        placement.absorb(stateOfTheRightEngine())

        XCTAssertEqual(workspaces.windowIds(in: 1), [300])
        XCTAssertFalse(placement.isParked(300))
    }

    func testAbsorbingPinsTheAnchorOfAnEngineThatHeldNoWindow() {
        placement.absorb(stateOfTheRightEngine())

        XCTAssertEqual(anchor.pinCount, 1)
    }
}
