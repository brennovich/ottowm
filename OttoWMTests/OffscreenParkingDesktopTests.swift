import CoreGraphics
import XCTest

private let originalFrame = CGRect(x: 100, y: 100, width: 800, height: 600)
private let pulledBackFrame = CGRect(x: 200, y: 300, width: 800, height: 600)

final class OffscreenParkingDesktopTests: XCTestCase {
    private let win = StubWindow(id: 100, frame: originalFrame)
    private let center = NotificationCenter()

    private let hiddenEdge = HiddenEdge(screen: StubScreen.standard)

    private lazy var windows = [win.id: win]

    private let parkedWindows = ParkedWindows()

    private lazy var desktop = OffscreenParkingDesktop(
        screen: StubScreen.standard,
        window: { [weak self] id in self?.windows[id] },
        notificationCenter: center
    )

    @discardableResult
    private func addWindow(_ id: CGWindowID, frame: CGRect, pid: pid_t = 0) -> StubWindow {
        let window = StubWindow(id: id, pid: pid, frame: frame)
        windows[id] = window
        return window
    }

    @discardableResult
    private func place(_ windowId: CGWindowID, at placement: Placement) -> [PlacementOutcome] {
        place([(windowId: windowId, placement: placement)])
    }

    /// Mirrors what `Engine` does around a placement: hands the desktop the frames the
    /// windows are owed, and records what comes back.
    @discardableResult
    private func place(_ placements: [(windowId: CGWindowID, placement: Placement)]) -> [PlacementOutcome] {
        let outcomes = desktop.place(placements.map {
            (windowId: $0.windowId, placement: $0.placement, owedFrame: parkedWindows.owedFrame(of: $0.windowId))
        })
        parkedWindows.record(outcomes)
        return outcomes
    }

    func testMoveStepsTheWindowWithoutAnimating() {
        XCTAssertTrue(desktop.move(100, Step(direction: .east, points: 15)))

        XCTAssertEqual(win.frame, originalFrame.offsetBy(dx: 15, dy: 0))
        XCTAssertEqual(win.animatedWriteCount, 0)
    }

    func testMoveStopsAtTheVisibleFrame() {
        desktop.move(100, Step(direction: .north, points: 500))

        XCTAssertEqual(win.frame.minY, StubScreen.standard.visibleFrame.minY)
    }

    func testMoveKeepsTheWindowOutOfTheHiddenEdge() {
        desktop.move(100, Step(direction: .east, points: 5000))
        desktop.move(100, Step(direction: .south, points: 5000))

        XCTAssertFalse(hiddenEdge.holds(win.frame))
    }

    func testMoveReportsAWindowThatNoLongerExists() {
        XCTAssertFalse(desktop.move(999, Step(direction: .east, points: 15)))
    }

    func testMoveLeavesAMinimizedWindowAlone() {
        win.isMinimized = true

        XCTAssertTrue(desktop.move(100, Step(direction: .east, points: 15)))

        XCTAssertEqual(win.frame, originalFrame)
    }

    func testPlaceCapturesFrameAndHidesThenRestores() {
        XCTAssertEqual(place(100, at: .parked), [.parked(100, owing: originalFrame)])
        XCTAssertEqual(win.frame, nubFrame(size: originalFrame.size))

        XCTAssertEqual(place(100, at: .active), [.activated(100)])
        XCTAssertEqual(win.frame, originalFrame)
    }

    func testPlaceIsIdempotent() {
        place(100, at: .parked)
        place(100, at: .parked)

        XCTAssertEqual(win.positionSetCount, 1)
        XCTAssertEqual(win.movableFrameCount, 1)

        place(100, at: .active)
        place(100, at: .active)

        XCTAssertEqual(win.positionSetCount, 2)
        XCTAssertEqual(win.frame, originalFrame)
    }

    func testPlaceWritesOnlyThePositionWhenTheSizeIsUnchanged() {
        place(100, at: .parked)
        place(100, at: .active)

        XCTAssertEqual(win.sizeSetCount, 0)
    }

    func testPlaceRestoresAWindowResizedWhileParkedWithAnimationsDisabled() {
        place(100, at: .parked)
        win.moveTo(nubFrame(size: CGSize(width: 400, height: 300)))

        place(100, at: .active)

        XCTAssertEqual(win.sizeSetCount, 1)
        XCTAssertEqual(win.frame, originalFrame)
        XCTAssertEqual(win.animatedWriteCount, 0)
    }

    func testPlaceNeverRecordsAHiddenEdgeFrameAsTheFrameOwed() {
        let stranded = addWindow(200, frame: nubFrame(size: originalFrame.size))

        place(200, at: .parked)
        place(200, at: .active)

        XCTAssertFalse(hiddenEdge.holds(stranded.frame))
    }

    func testPlaceRecoversAStrandedWindowItNeverParked() {
        let stranded = addWindow(200, frame: nubFrame(size: originalFrame.size))

        XCTAssertEqual(place(200, at: .active), [.activated(200)])
        XCTAssertFalse(hiddenEdge.holds(stranded.frame))
    }

    func testPlaceLeavesAnUnparkedWindowOnScreenAlone() {
        XCTAssertEqual(place(100, at: .active), [.activated(100)])
        XCTAssertEqual(win.positionSetCount, 0)
        XCTAssertEqual(win.frame, originalFrame)
    }

    func testPlaceLeavesAMinimizedWindowWhereItIsOwingNothing() {
        win.isMinimized = true

        XCTAssertEqual(place(100, at: .parked), [.activated(100)])
        XCTAssertEqual(win.positionSetCount, 0)
    }

    func testPlaceReportsAMissingWindow() {
        XCTAssertEqual(place(999, at: .parked), [.gone(999)])
        XCTAssertEqual(place(999, at: .active), [.gone(999)])
    }

    func testPlaceReportsAParkedWindowThatVanished() {
        place(100, at: .parked)
        windows[100] = nil

        XCTAssertEqual(place(100, at: .parked), [.gone(100)])
        XCTAssertEqual(place(100, at: .active), [.gone(100)])
    }

    func testPlaceParksAndRestoresEveryWindowOfABatch() {
        let other = addWindow(200, frame: pulledBackFrame)

        let outcomes = place([(windowId: 100, placement: .parked), (windowId: 200, placement: .parked)])

        XCTAssertEqual(Set(outcomes), [.parked(100, owing: originalFrame), .parked(200, owing: pulledBackFrame)])
        XCTAssertEqual(win.frame, nubFrame(size: originalFrame.size))
        XCTAssertEqual(other.frame, nubFrame(size: pulledBackFrame.size))

        place([(windowId: 100, placement: .active), (windowId: 200, placement: .active)])

        XCTAssertEqual(win.frame, originalFrame)
        XCTAssertEqual(other.frame, pulledBackFrame)
    }

    func testPlaceReportsTheWindowsOfABatchThatAreGone() {
        let outcomes = place([(windowId: 100, placement: .parked), (windowId: 999, placement: .parked)])

        XCTAssertEqual(Set(outcomes), [.parked(100, owing: originalFrame), .gone(999)])
    }

    func testPlaceOverlapsTheMovesOfDifferentApplications() {
        let batch = (1...8).map { addWindow(CGWindowID($0) * 10, frame: originalFrame, pid: pid_t($0)) }
        let firstMove = DispatchSemaphore(value: 1)
        let anotherMove = DispatchSemaphore(value: 0)
        for window in batch {
            window.onSetPosition = {
                if firstMove.wait(timeout: .now()) == .success {
                    XCTAssertEqual(anotherMove.wait(timeout: .now() + 2), .success)
                } else {
                    anotherMove.signal()
                }
            }
        }

        place(batch.map { (windowId: $0.id, placement: .parked) })

        XCTAssertEqual(Set(batch.map(\.frame)), [nubFrame(size: originalFrame.size)])
    }

    func testPlaceKeepsTheWindowsOfOneApplicationOnOneThread() {
        let batch = (1...8).map { addWindow(CGWindowID($0) * 10, frame: originalFrame, pid: 42) }

        place(batch.map { (windowId: $0.id, placement: .parked) })

        XCTAssertEqual(Set(batch.compactMap(\.positionSetThread)).count, 1)
    }

    func testFocusReportsWhetherTheWindowWasStillThere() {
        XCTAssertTrue(desktop.focus(100))
        XCTAssertEqual(win.focusCount, 1)

        XCTAssertFalse(desktop.focus(200))
    }

    func testPlacingEveryParkedWindowActiveBringsThemBack() {
        let other = addWindow(200, frame: CGRect(x: 300, y: 200, width: 400, height: 300))
        let onScreen = addWindow(300, frame: CGRect(x: 50, y: 50, width: 200, height: 200))
        place(100, at: .parked)
        place(200, at: .parked)

        place(parkedWindows.all.map { (windowId: $0.windowId, placement: .active) })

        XCTAssertEqual(win.frame, originalFrame)
        XCTAssertEqual(other.frame, CGRect(x: 300, y: 200, width: 400, height: 300))
        XCTAssertEqual(parkedWindows.all.map(\.windowId), [])
        XCTAssertEqual(onScreen.positionSetCount, 0)
    }

    func testAWindowForgottenWhileParkedIsRecoveredFromTheCorner() {
        place(100, at: .parked)
        parkedWindows.forget(100)

        place(100, at: .active)

        XCTAssertEqual(win.frame, hiddenEdge.recovered(from: nubFrame(size: originalFrame.size)))
    }

    func testRecoverUnparksWindowsStuckInHiddenCorner() {
        let stuck = addWindow(200, frame: CGRect(x: 1791, y: 100, width: 800, height: 600))

        _ = desktop.recover([stuck.snapshot(), win.snapshot()])

        XCTAssertEqual(stuck.positionSetCount, 1)
        XCTAssertFalse(hiddenEdge.holds(stuck.frame))
        XCTAssertEqual(win.positionSetCount, 0)
    }

    func testRecoverShrinksAWindowLargerThanTheVisibleFrameWithoutAnimating() {
        let stuck = addWindow(200, frame: CGRect(x: 1791, y: 100, width: 3000, height: 600))

        _ = desktop.recover([stuck.snapshot()])

        XCTAssertEqual(stuck.sizeSetCount, 1)
        XCTAssertEqual(stuck.frame.width, StubScreen.standard.visibleFrame.width)
        XCTAssertEqual(stuck.animatedWriteCount, 0)
    }

    func testStartWatchingReportsANativeSpaceChange() {
        var changes = 0

        desktop.startWatching { changes += 1 }
        center.postNativeSpaceChange()

        XCTAssertEqual(changes, 1)
    }

    func testStartWatchingReplacesThePreviousSubscription() {
        var first = 0
        var second = 0

        desktop.startWatching { first += 1 }
        desktop.startWatching { second += 1 }
        center.postNativeSpaceChange()

        XCTAssertEqual(first, 0)
        XCTAssertEqual(second, 1)
    }

    func testReparkParksAWindowPulledBackOnScreenWithoutAnimations() {
        place(100, at: .parked)
        win.moveTo(pulledBackFrame)

        desktop.repark(parkedWindows.all)

        XCTAssertEqual(win.frame, nubFrame(size: originalFrame.size))
        XCTAssertEqual(win.animatedWriteCount, 0)

        place(100, at: .active)

        XCTAssertEqual(win.frame, originalFrame)
    }

    func testReparkLeavesAWindowAtTheHiddenEdgeAlone() {
        place(100, at: .parked)

        desktop.repark(parkedWindows.all)

        XCTAssertEqual(win.positionSetCount, 1)
    }
}
