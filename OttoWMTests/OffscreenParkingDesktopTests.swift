import CoreGraphics
import XCTest

private let originalFrame = CGRect(x: 100, y: 100, width: 800, height: 600)
private let pulledBackFrame = CGRect(x: 200, y: 300, width: 800, height: 600)

final class OffscreenParkingDesktopTests: XCTestCase {
    private let win = StubWindow(id: 100, frame: originalFrame)
    private let center = NotificationCenter()
    private let screens = StubScreen(main: .standard)

    private let hiddenEdge = HiddenEdge(display: .standard)

    private lazy var windows = [win.id: win]

    private let parkedWindows = ParkedWindows()

    private lazy var desktop = OffscreenParkingDesktop(
        screens: screens,
        window: { [weak self] id in self?.windows[id] },
        notificationCenter: center,
        screenNotificationCenter: center
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

        XCTAssertEqual(win.frame.minY, Display.standard.visibleFrame.minY)
    }

    func testResizeChangesTheSizeFromTheTopLeftWithoutAnimating() {
        reframe(100, .resize(Resize(change: .wider, points: 15)))

        XCTAssertEqual(win.frame, CGRect(x: 100, y: 100, width: 815, height: 600))
        XCTAssertEqual(win.positionSetCount, 0)
        XCTAssertEqual(win.animatedWriteCount, 0)
    }

    func testResizeStopsAtTheVisibleFrame() {
        reframe(100, .resize(Resize(change: .taller, points: 5000)))

        XCTAssertEqual(win.frame.maxY, Display.standard.visibleFrame.maxY)
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

    /// A window rarely settles at the frame it was given: Terminal rounds its height to
    /// whole rows. A window within the tolerance counts as filling the target.
    func testMaximizeTakesAWindowShortOfTheFilledFrameBackToTheFrameHandedIn() {
        let short = addWindow(101, frame: CGRect(x: 15, y: 53, width: 1762, height: 1051))

        XCTAssertEqual(reframe(short.id, .maximize(restoring: originalFrame)), [.active(short.id)])
        XCTAssertEqual(short.frame, originalFrame)
    }

    /// A window that already fills the screen has no frame to restore to, and its current
    /// frame must not be recorded: restoring it would leave the window filled. The window
    /// settles a few points short of the filled frame, which still counts as filled.
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
    }

    /// One record serves every target, so a window in one half still fills the screen
    /// rather than restoring to the frame that record holds.
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
        XCTAssertEqual(reframe(100, .park(from: nil)), [.parked(100, from: originalFrame)])
        XCTAssertEqual(win.frame, hiddenEdgeFrame(size: originalFrame.size))

        XCTAssertEqual(unpark(100), [.active(100)])
        XCTAssertEqual(win.frame, originalFrame)
        XCTAssertEqual(win.sizeSetCount, 0)
    }

    func testParkingFromAKnownFrameHidesTheWindowSizedByItWhereverItSits() {
        let known = CGRect(x: 50, y: 60, width: 640, height: 480)

        XCTAssertEqual(reframe(100, .park(from: known)), [.parked(100, from: known)])
        XCTAssertEqual(win.frame, hiddenEdgeFrame(size: known.size))
    }

    func testParkingAMinimizedWindowFromAKnownFrameKeepsIt() {
        win.isMinimized = true

        XCTAssertEqual(reframe(100, .park(from: originalFrame)), [.parked(100, from: originalFrame)])
        XCTAssertEqual(win.positionSetCount, 0)
    }

    func testUnparkingRestoresAWindowResizedWhileParkedWithoutAnimating() {
        reframe(100, .park(from: nil))
        win.moveTo(hiddenEdgeFrame(size: CGSize(width: 400, height: 300)))

        unpark(100)

        XCTAssertEqual(win.sizeSetCount, 1)
        XCTAssertEqual(win.frame, originalFrame)
        XCTAssertEqual(win.animatedWriteCount, 0)
    }

    func testParkingNeverRecordsAHiddenEdgeFrameAsTheFrameParkedFrom() {
        let strandedFrame = hiddenEdgeFrame(size: originalFrame.size)
        addWindow(200, frame: strandedFrame)

        XCTAssertEqual(reframe(200, .park(from: nil)), [.parked(200, from: CGRect(x: 496, y: 279, width: 800, height: 600))])
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

        XCTAssertEqual(reframe(100, .park(from: nil)), [.active(100)])
        XCTAssertEqual(win.positionSetCount, 0)
    }

    func testUnparkingAMinimizedWindowKeepsTheFrameItWasParkedFrom() {
        reframe(100, .park(from: nil))
        win.isMinimized = true

        XCTAssertEqual(unpark(100), [.parked(100, from: originalFrame)])
        XCTAssertEqual(parkedWindows.parkedFrom(of: 100), originalFrame)
        XCTAssertEqual(win.positionSetCount, 1)
    }

    func testReportsAMissingWindowWhetherItWasParkedOrNeverSeen() {
        reframe(100, .park(from: nil))
        windows[100] = nil

        for change in [FrameChange.park(from: nil), .unpark(nil)] {
            XCTAssertEqual(reframe(100, change), [.gone(100)])
            XCTAssertEqual(reframe(999, change), [.gone(999)])
        }
    }

    func testParksAndRestoresEveryWindowOfABatchReportingTheOnesThatAreGone() {
        let other = addWindow(200, frame: pulledBackFrame)

        let outcomes = reframe([
            (windowId: 100, change: .park(from: nil)), (windowId: 200, change: .park(from: nil)), (windowId: 999, change: .park(from: nil)),
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

        reframe(batch.map { (windowId: $0.id, change: .park(from: nil)) })

        XCTAssertEqual(batch.map(\.frame), Array(repeating: hiddenEdgeFrame(size: originalFrame.size), count: batch.count))
    }

    func testKeepsTheWindowsOfOneApplicationOnOneThread() {
        let batch = (1...8).map { addWindow(CGWindowID($0) * 10, frame: originalFrame, pid: 42) }

        reframe(batch.map { (windowId: $0.id, change: .park(from: nil)) })

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
        var events: [DesktopEvent] = []

        desktop.startWatching { events.append($0) }
        center.postNativeSpaceChange()

        XCTAssertEqual(events, [.nativeSpaceChange])
    }

    func testStartWatchingReplacesThePreviousSubscription() {
        var first = 0
        var second = 0

        desktop.startWatching { _ in first += 1 }
        desktop.startWatching { _ in second += 1 }
        center.postNativeSpaceChange()
        screens.main = .external
        center.postScreenParametersChange()

        XCTAssertEqual(first, 0)
        XCTAssertEqual(second, 2)
    }

    func testAScreenParametersChangeToAnotherDisplayIsReportedOnceAndMovesTheHiddenEdge() {
        var events: [DesktopEvent] = []
        desktop.startWatching { events.append($0) }

        screens.main = .external
        center.postScreenParametersChange()
        center.postScreenParametersChange()

        XCTAssertEqual(events, [.displayChange(from: .standard, to: .external)])
        XCTAssertEqual(desktop.display, .external)
        reframe(100, .park(from: nil))
        XCTAssertEqual(win.frame, hiddenEdgeFrame(size: originalFrame.size, on: .external))
    }

    func testAScreenParametersChangeWithNoDisplayKeepsTheLastOne() {
        var events: [DesktopEvent] = []
        desktop.startWatching { events.append($0) }

        screens.main = nil
        center.postScreenParametersChange()

        XCTAssertEqual(events, [])
        XCTAssertEqual(desktop.display, .standard)
    }

    func testReparkParksAWindowPulledBackOnScreenWithoutAnimations() {
        reframe(100, .park(from: nil))
        win.moveTo(pulledBackFrame)

        desktop.repark(parkedWindows.all)

        XCTAssertEqual(win.frame, hiddenEdgeFrame(size: originalFrame.size))
        XCTAssertEqual(win.animatedWriteCount, 0)

        unpark(100)

        XCTAssertEqual(win.frame, originalFrame)
    }

    func testReparkLeavesAWindowAtTheHiddenEdgeAlone() {
        reframe(100, .park(from: nil))

        desktop.repark(parkedWindows.all)

        XCTAssertEqual(win.positionSetCount, 1)
    }
}
