import CoreGraphics
import XCTest

private let originalFrame = CGRect(x: 100, y: 100, width: 800, height: 600)
private let pulledBackFrame = CGRect(x: 200, y: 300, width: 800, height: 600)

final class ParkingDesktopTests: XCTestCase {
    private let win = StubWindow(id: 100, frame: originalFrame)
    private let center = NotificationCenter()
    private let screens = StubScreen(main: .standard)

    private let hiddenEdge = HiddenEdge(display: .standard)

    private lazy var windows = [win.id: win]

    private let parkedWindows = ParkedWindows()

    private lazy var desktop = ParkingDesktop(
        screens: screens,
        window: { [weak self] id in self?.windows[id] },
        spacing: 15,
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
        reframe([FrameRequest(windowId: windowId, change: change)])
    }

    /// Mirrors what `WindowPlacement` does around an unpark: hands the desktop the frame the
    /// window was parked from.
    @discardableResult
    private func unpark(_ windowId: CGWindowID) -> [FrameOutcome] {
        reframe(windowId, .unpark(parkedWindows.parkedFrom(of: windowId)))
    }

    @discardableResult
    private func reframe(_ requests: [FrameRequest]) -> [FrameOutcome] {
        let outcomes = desktop.reframe(requests)
        parkedWindows.record(outcomes)
        return outcomes
    }

    func testReframeWritesTheFrameOfTheWorkAreaWithoutAnimating() {
        desktop.spacing = 30

        reframe(100, .move(.east))

        XCTAssertEqual(win.frame, originalFrame.offsetBy(dx: 30, dy: 0))
        XCTAssertEqual(win.animatedWriteCount, 0)
    }

    func testAWriteSetsOnlyThePartOfTheFrameThatChanges() {
        let resized = addWindow(101, frame: originalFrame)

        reframe([
            FrameRequest(windowId: win.id, change: .move(.east)),
            FrameRequest(windowId: resized.id, change: .resize(.wider)),
        ])

        XCTAssertEqual(win.sizeSetCount, 0)
        XCTAssertEqual(resized.positionSetCount, 0)
    }

    func testIsMaximizedDelegatesToTheFilledFrame() {
        XCTAssertTrue(desktop.isMaximized(CGRect(x: 15, y: 53, width: 1762, height: 1045)))
        XCTAssertFalse(desktop.isMaximized(originalFrame))
    }

    func testAWindowThatIsNotMovableIsNotWrittenAndKeepsItsKnownOutcome() {
        win.isMinimized = true

        XCTAssertEqual(reframe(100, .maximize(restoring: originalFrame)), [.filled(100, from: originalFrame)])
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
            FrameRequest(windowId: 100, change: .park(from: nil)),
            FrameRequest(windowId: 200, change: .park(from: nil)),
            FrameRequest(windowId: 999, change: .park(from: nil)),
        ])

        XCTAssertEqual(
            Set(outcomes), [.parked(100, from: originalFrame), .parked(200, from: pulledBackFrame), .gone(999)]
        )
        XCTAssertEqual(win.frame, hiddenEdgeFrame(size: originalFrame.size))
        XCTAssertEqual(other.frame, hiddenEdgeFrame(size: pulledBackFrame.size))

        reframe([100, 200].map { FrameRequest(windowId: $0, change: .unpark(parkedWindows.parkedFrom(of: $0))) })

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

        reframe(batch.map { FrameRequest(windowId: $0.id, change: .park(from: nil)) })

        XCTAssertEqual(batch.map(\.frame), Array(repeating: hiddenEdgeFrame(size: originalFrame.size), count: batch.count))
    }

    func testSuspendsTheAnimationsOfAnApplicationOnceForItsBatch() {
        let batch = (1...3).map { addWindow(CGWindowID($0) * 10, frame: originalFrame, pid: 42) }

        reframe(batch.map { FrameRequest(windowId: $0.id, change: .park(from: nil)) })

        XCTAssertEqual(batch.map(\.withoutAnimationsCount).reduce(0, +), 1)
        XCTAssertEqual(batch.map(\.animatedWriteCount), [0, 0, 0])
    }

    func testKeepsTheWindowsOfOneApplicationOnOneThread() {
        let batch = (1...8).map { addWindow(CGWindowID($0) * 10, frame: originalFrame, pid: 42) }

        reframe(batch.map { FrameRequest(windowId: $0.id, change: .park(from: nil)) })

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

    func testEverySubscriptionReceivesEachEventOnce() {
        var first = 0
        var second = 0

        desktop.startWatching { _ in first += 1 }
        desktop.startWatching { _ in second += 1 }
        center.postNativeSpaceChange()
        screens.main = .external
        center.postScreenParametersChange()

        XCTAssertEqual(first, 2)
        XCTAssertEqual(second, 2)
    }

    func testAScreenParametersChangeToAnotherDisplayIsReportedOnceAndMovesTheHiddenEdge() {
        var events: [DesktopEvent] = []
        desktop.startWatching { events.append($0) }

        screens.main = .external
        center.postScreenParametersChange()
        center.postScreenParametersChange()

        XCTAssertEqual(events, [.displayChange(DisplayChange(from: .standard, to: .external)), .screenParametersChange])
        XCTAssertEqual(desktop.display, .external)
        reframe(100, .park(from: nil))
        XCTAssertEqual(win.frame, hiddenEdgeFrame(size: originalFrame.size, on: .external))
    }

    func testAScreenParametersChangeOfTheGeometryOfTheSameDisplayIsReported() {
        var events: [DesktopEvent] = []
        desktop.startWatching { events.append($0) }
        let dockMoved = Display(
            id: Display.standard.id,
            fullFrame: Display.standard.fullFrame,
            visibleFrame: CGRect(x: 0, y: 38, width: 1792, height: 1000)
        )

        screens.main = dockMoved
        center.postScreenParametersChange()

        XCTAssertEqual(events, [.displayChange(DisplayChange(from: .standard, to: dockMoved))])
    }

    func testAScreenParametersChangeThatKeepsTheDisplayIsReported() {
        var events: [DesktopEvent] = []
        desktop.startWatching { events.append($0) }

        center.postScreenParametersChange()

        XCTAssertEqual(events, [.screenParametersChange])
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
