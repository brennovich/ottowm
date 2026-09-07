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
    private func reframe(_ windowId: CGWindowID, _ change: FrameChange) -> [FrameOutcome] {
        reframe([(windowId: windowId, change: change)])
    }

    /// Mirrors what `WindowPlacement` does around an unpark: hands the desktop the frame the
    /// window was parked from.
    @discardableResult
    private func unpark(_ windowId: CGWindowID) -> [FrameOutcome] {
        reframe(windowId, .unpark(parkedWindows.parkedFrom(of: windowId)))
    }

    @discardableResult
    private func reframe(_ changes: [(windowId: CGWindowID, change: FrameChange)]) -> [FrameOutcome] {
        let outcomes = desktop.reframe(changes)
        parkedWindows.record(outcomes)
        return outcomes
    }

    func testStepMovesTheWindowWithoutAnimating() {
        reframe(100, .step(Step(direction: .east, points: 15)))

        XCTAssertEqual(win.frame, originalFrame.offsetBy(dx: 15, dy: 0))
        XCTAssertEqual(win.animatedWriteCount, 0)
    }

    func testStepStopsAtTheVisibleFrame() {
        reframe(100, .step(Step(direction: .north, points: 500)))

        XCTAssertEqual(win.frame.minY, StubScreen.standard.visibleFrame.minY)
    }

    func testCenterPutsTheWindowInTheMiddleOfTheVisibleFrame() {
        reframe(100, .center)

        XCTAssertEqual(win.frame, CGRect(x: 496, y: 279, width: 800, height: 600))
    }

    func testCenterPushesAWindowLargerThanTheVisibleFrameOffscreen() {
        let oversized = addWindow(101, frame: CGRect(x: 0, y: 0, width: 2000, height: 1200))

        reframe(oversized.id, .center)

        XCTAssertEqual(oversized.frame, CGRect(x: -104, y: -21, width: 2000, height: 1200))
    }

    func testMaximizeFillsTheVisibleFrameInsetOnEveryEdge() {
        XCTAssertEqual(reframe(100, .maximize(restoring: nil)), [.filled(100, from: originalFrame)])
        XCTAssertEqual(win.frame, CGRect(x: 15, y: 53, width: 1762, height: 1052))
        XCTAssertEqual(win.animatedWriteCount, 0)
    }

    /// A window rarely settles at the frame it was given: Terminal quantizes its height to
    /// whole rows. The frame handed in is what says the window is maximized, not its size.
    func testMaximizeTakesAWindowBackToTheFrameHandedInWhateverItsSize() {
        let short = addWindow(101, frame: CGRect(x: 15, y: 53, width: 1762, height: 1051))

        XCTAssertEqual(reframe(short.id, .maximize(restoring: originalFrame)), [.active(short.id)])
        XCTAssertEqual(short.frame, originalFrame)
    }

    /// A window that already fills the screen has no frame to go back to, and the frame it
    /// is at is not one worth recording: taking it back there would leave it filled. The
    /// window settles a few points short of the filled frame, which still counts as filled.
    func testMaximizeLeavesAFilledWindowAloneWithNothingToRestore() {
        let shortOfFilled = CGRect(x: 15, y: 53, width: 1762, height: 1045)
        let filled = addWindow(101, frame: shortOfFilled)

        XCTAssertEqual(reframe(filled.id, .maximize(restoring: nil)), [.active(filled.id)])
        XCTAssertEqual(filled.frame, shortOfFilled)
    }

    func testRestoringAWindowThatIsNotMovableKeepsTheFrameToGoBackTo() {
        win.isMinimized = true

        XCTAssertEqual(reframe(100, .maximize(restoring: originalFrame)), [.filled(100, from: originalFrame)])
        XCTAssertEqual(win.positionSetCount, 0)
    }

    func testFillTakesTheHalfOfTheFrameAMaximizeFills() {
        XCTAssertEqual(reframe(100, .fill(.west, restoring: nil)), [.filled(100, from: originalFrame)])
        XCTAssertEqual(win.frame, CGRect(x: 15, y: 53, width: 873.5, height: 1052))
        XCTAssertEqual(win.animatedWriteCount, 0)
    }

    func testFillTakesAWindowAlreadyInThatHalfBackToTheFrameHandedIn() {
        let west = addWindow(101, frame: CGRect(x: 15, y: 53, width: 873.5, height: 1052))

        XCTAssertEqual(reframe(west.id, .fill(.west, restoring: originalFrame)), [.active(west.id)])
        XCTAssertEqual(west.frame, originalFrame)
    }

    /// One record serves every target, so a window standing in one half still fills the
    /// screen rather than going back to the frame that record holds.
    func testFillingAcrossTargetsMovesOnRatherThanRestoring() {
        let west = addWindow(101, frame: CGRect(x: 15, y: 53, width: 873.5, height: 1052))

        XCTAssertEqual(
            reframe(west.id, .maximize(restoring: originalFrame)),
            [.filled(west.id, from: CGRect(x: 15, y: 53, width: 873.5, height: 1052))]
        )
        XCTAssertEqual(west.frame, CGRect(x: 15, y: 53, width: 1762, height: 1052))
    }

    func testReportsAWindowThatNoLongerExists() {
        XCTAssertEqual(reframe(999, .step(Step(direction: .east, points: 15))), [.gone(999)])
    }

    func testStepLeavesAMinimizedWindowAlone() {
        win.isMinimized = true

        XCTAssertEqual(reframe(100, .step(Step(direction: .east, points: 15))), [.active(100)])

        XCTAssertEqual(win.frame, originalFrame)
    }

    func testParkingCapturesTheFrameAndUnparkingRestoresIt() {
        XCTAssertEqual(reframe(100, .park), [.parked(100, from: originalFrame)])
        XCTAssertEqual(win.frame, hiddenEdgeFrame(size: originalFrame.size))

        XCTAssertEqual(unpark(100), [.active(100)])
        XCTAssertEqual(win.frame, originalFrame)
        XCTAssertEqual(win.sizeSetCount, 0)
    }

    func testUnparkingRestoresAWindowResizedWhileParkedWithoutAnimating() {
        reframe(100, .park)
        win.moveTo(hiddenEdgeFrame(size: CGSize(width: 400, height: 300)))

        unpark(100)

        XCTAssertEqual(win.sizeSetCount, 1)
        XCTAssertEqual(win.frame, originalFrame)
        XCTAssertEqual(win.animatedWriteCount, 0)
    }

    func testParkingNeverRecordsAHiddenEdgeFrameAsTheFrameParkedFrom() {
        let strandedFrame = hiddenEdgeFrame(size: originalFrame.size)
        addWindow(200, frame: strandedFrame)

        XCTAssertEqual(reframe(200, .park), [.parked(200, from: CGRect(x: 496, y: 279, width: 800, height: 600))])
    }

    func testUnparkingRecoversAStrandedWindowItNeverParked() {
        let strandedFrame = hiddenEdgeFrame(size: originalFrame.size)
        let stranded = addWindow(200, frame: strandedFrame)

        XCTAssertEqual(unpark(200), [.active(200)])
        XCTAssertEqual(stranded.frame, CGRect(x: 496, y: 279, width: 800, height: 600))
    }

    func testUnparkingLeavesAWindowOnScreenAlone() {
        XCTAssertEqual(unpark(100), [.active(100)])
        XCTAssertEqual(win.positionSetCount, 0)
        XCTAssertEqual(win.frame, originalFrame)
    }

    func testParkingAMinimizedWindowRecordsNothing() {
        win.isMinimized = true

        XCTAssertEqual(reframe(100, .park), [.active(100)])
        XCTAssertEqual(win.positionSetCount, 0)
    }

    func testUnparkingAMinimizedWindowKeepsTheFrameItWasParkedFrom() {
        reframe(100, .park)
        win.isMinimized = true

        XCTAssertEqual(unpark(100), [.parked(100, from: originalFrame)])
        XCTAssertEqual(parkedWindows.parkedFrom(of: 100), originalFrame)
        XCTAssertEqual(win.positionSetCount, 1)
    }

    func testReportsAMissingWindowWhetherItWasParkedOrNeverSeen() {
        reframe(100, .park)
        windows[100] = nil

        for change in [FrameChange.park, .unpark(nil)] {
            XCTAssertEqual(reframe(100, change), [.gone(100)])
            XCTAssertEqual(reframe(999, change), [.gone(999)])
        }
    }

    func testParksAndRestoresEveryWindowOfABatchReportingTheOnesThatAreGone() {
        let other = addWindow(200, frame: pulledBackFrame)

        let outcomes = reframe([
            (windowId: 100, change: .park), (windowId: 200, change: .park), (windowId: 999, change: .park),
        ])

        XCTAssertEqual(
            Set(outcomes), [.parked(100, from: originalFrame), .parked(200, from: pulledBackFrame), .gone(999)]
        )
        XCTAssertEqual(win.frame, hiddenEdgeFrame(size: originalFrame.size))
        XCTAssertEqual(other.frame, hiddenEdgeFrame(size: pulledBackFrame.size))

        reframe([100, 200].map { (windowId: $0, change: .unpark(parkedWindows.parkedFrom(of: $0))) })

        XCTAssertEqual(win.frame, originalFrame)
        XCTAssertEqual(other.frame, pulledBackFrame)
    }

    func testOverlapsTheMovesOfDifferentApplications() {
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

        reframe(batch.map { (windowId: $0.id, change: .park) })

        XCTAssertEqual(Set(batch.map(\.frame)), [hiddenEdgeFrame(size: originalFrame.size)])
    }

    func testKeepsTheWindowsOfOneApplicationOnOneThread() {
        let batch = (1...8).map { addWindow(CGWindowID($0) * 10, frame: originalFrame, pid: 42) }

        reframe(batch.map { (windowId: $0.id, change: .park) })

        XCTAssertEqual(Set(batch.compactMap(\.positionSetThread)).count, 1)
    }

    func testFocusReportsWhetherTheWindowWasStillThere() {
        XCTAssertTrue(desktop.focus(100))
        XCTAssertEqual(win.focusCount, 1)

        XCTAssertFalse(desktop.focus(200))
    }

    func testRecoverUnparksWindowsStuckAtTheHiddenEdgeWithoutAnimating() {
        let stuck = addWindow(200, frame: CGRect(x: 1791, y: 100, width: 800, height: 600))

        _ = desktop.recover([stuck.snapshot(), win.snapshot()])

        XCTAssertEqual(stuck.positionSetCount, 1)
        XCTAssertFalse(hiddenEdge.holds(stuck.frame))
        XCTAssertEqual(stuck.animatedWriteCount, 0)
        XCTAssertEqual(win.positionSetCount, 0)
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
        reframe(100, .park)
        win.moveTo(pulledBackFrame)

        desktop.repark(parkedWindows.all)

        XCTAssertEqual(win.frame, hiddenEdgeFrame(size: originalFrame.size))
        XCTAssertEqual(win.animatedWriteCount, 0)

        unpark(100)

        XCTAssertEqual(win.frame, originalFrame)
    }

    func testReparkLeavesAWindowAtTheHiddenEdgeAlone() {
        reframe(100, .park)

        desktop.repark(parkedWindows.all)

        XCTAssertEqual(win.positionSetCount, 1)
    }
}
