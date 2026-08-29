import CoreGraphics
import XCTest

private let originalFrame = CGRect(x: 100, y: 100, width: 800, height: 600)
private let pulledBackFrame = CGRect(x: 200, y: 300, width: 800, height: 600)

final class OffscreenParkingDesktopTests: XCTestCase {
    private let win = StubWindow(id: 100, frame: originalFrame)
    private var focusedWindowId: CGWindowID?
    private let center = NotificationCenter()

    private let hiddenEdge = OffscreenParkingDesktop.HiddenEdge(screen: StubScreen.standard)

    private lazy var windows = [win.id: win]

    private lazy var desktop = OffscreenParkingDesktop(
        screen: StubScreen.standard,
        window: { [weak self] id in self?.windows[id] },
        focusedWindowId: { [weak self] in self?.focusedWindowId },
        notificationCenter: center
    )

    @discardableResult
    private func addWindow(_ id: CGWindowID, frame: CGRect, pid: pid_t = 0) -> StubWindow {
        let window = StubWindow(id: id, pid: pid, frame: frame)
        windows[id] = window
        return window
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

    func testMoveLeavesAParkedWindowAtTheHiddenEdge() {
        desktop.place(100, at: .storage)

        XCTAssertTrue(desktop.move(100, Step(direction: .west, points: 15)))

        XCTAssertEqual(win.frame, nubFrame(size: originalFrame.size))

        desktop.place(100, at: .active)

        XCTAssertEqual(win.frame, originalFrame)
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
        XCTAssertEqual(desktop.placement(of: 100), .active)

        desktop.place(100, at: .storage)

        XCTAssertEqual(win.frame, nubFrame(size: originalFrame.size))
        XCTAssertEqual(desktop.placement(of: 100), .storage)

        desktop.place(100, at: .active)

        XCTAssertEqual(win.frame, originalFrame)
        XCTAssertEqual(desktop.placement(of: 100), .active)
    }

    func testPlaceIsIdempotent() {
        desktop.place(100, at: .storage)
        desktop.place(100, at: .storage)

        XCTAssertEqual(win.positionSetCount, 1)

        desktop.place(100, at: .active)
        desktop.place(100, at: .active)

        XCTAssertEqual(win.positionSetCount, 2)
        XCTAssertEqual(win.frame, originalFrame)
    }

    func testPlaceDoesNotReadTheFrameOfAnAlreadyParkedWindow() {
        desktop.place(100, at: .storage)
        desktop.place(100, at: .storage)

        XCTAssertEqual(win.movableFrameCount, 1)
    }

    func testPlaceWritesOnlyThePositionWhenTheSizeIsUnchanged() {
        desktop.place(100, at: .storage)
        desktop.place(100, at: .active)

        XCTAssertEqual(win.sizeSetCount, 0)
    }

    func testPlaceRestoresAWindowResizedWhileParkedWithAnimationsDisabled() {
        desktop.place(100, at: .storage)
        win.moveTo(nubFrame(size: CGSize(width: 400, height: 300)))

        desktop.place(100, at: .active)

        XCTAssertEqual(win.sizeSetCount, 1)
        XCTAssertEqual(win.frame, originalFrame)
        XCTAssertEqual(win.animatedWriteCount, 0)
    }

    func testRecoverWritesTheFrameWithAnimationsDisabled() {
        let stuck = addWindow(200, frame: CGRect(x: 1791, y: 100, width: 3000, height: 600))

        _ = desktop.recover([stuck.snapshot()])

        XCTAssertEqual(stuck.positionSetCount + stuck.sizeSetCount, 2)
        XCTAssertEqual(stuck.animatedWriteCount, 0)
    }

    func testPlaceNeverRecordsAHiddenEdgeFrameAsTheFrameOwed() {
        let stranded = addWindow(200, frame: nubFrame(size: originalFrame.size))

        desktop.place(200, at: .storage)
        desktop.place(200, at: .active)

        XCTAssertFalse(hiddenEdge.holds(stranded.frame))
    }

    func testPlaceRecoversAStrandedWindowItNeverParked() {
        let stranded = addWindow(200, frame: nubFrame(size: originalFrame.size))

        desktop.place(200, at: .active)

        XCTAssertFalse(hiddenEdge.holds(stranded.frame))
        XCTAssertEqual(desktop.placement(of: 200), .active)
    }

    func testPlaceLeavesAnUnparkedWindowOnScreenAloneAndReportsItAsStillThere() {
        XCTAssertTrue(desktop.place(100, at: .active))
        XCTAssertEqual(win.positionSetCount, 0)
        XCTAssertEqual(win.frame, originalFrame)
    }

    func testPlaceSkipsMinimizedWindows() {
        win.isMinimized = true

        desktop.place(100, at: .storage)

        XCTAssertEqual(win.positionSetCount, 0)
        XCTAssertEqual(desktop.placement(of: 100), .active)
    }

    func testPlaceReportsAMissingWindowAndLeavesItActive() {
        XCTAssertFalse(desktop.place(999, at: .storage))
        XCTAssertFalse(desktop.place(999, at: .active))
        XCTAssertEqual(desktop.placement(of: 999), .active)
    }

    func testPlaceReportsAnOutOfReachWindowAsStillThere() {
        win.isMinimized = true

        XCTAssertTrue(desktop.place(100, at: .storage))
    }

    func testPlaceReportsAParkedWindowThatVanished() {
        desktop.place(100, at: .storage)
        windows[100] = nil

        XCTAssertFalse(desktop.place(100, at: .storage))
        XCTAssertFalse(desktop.place(100, at: .active))
    }

    func testPlaceMovesEveryWindowOfABatch() {
        let other = addWindow(200, frame: pulledBackFrame)

        let gone = desktop.place([(windowId: 100, placement: .storage), (windowId: 200, placement: .storage)])

        XCTAssertEqual(gone, [])
        XCTAssertEqual(win.frame, nubFrame(size: originalFrame.size))
        XCTAssertEqual(other.frame, nubFrame(size: pulledBackFrame.size))
        XCTAssertEqual(desktop.placement(of: 100), .storage)
        XCTAssertEqual(desktop.placement(of: 200), .storage)
    }

    func testPlaceReportsTheWindowsOfABatchThatAreGone() {
        let gone = desktop.place([(windowId: 100, placement: .storage), (windowId: 999, placement: .storage)])

        XCTAssertEqual(gone, [999])
        XCTAssertEqual(desktop.placement(of: 100), .storage)
    }

    func testPlaceRestoresEveryWindowOfABatchToTheFrameItWasParkedFrom() {
        let other = addWindow(200, frame: pulledBackFrame)
        desktop.place([(windowId: 100, placement: .storage), (windowId: 200, placement: .storage)])

        desktop.place([(windowId: 100, placement: .active), (windowId: 200, placement: .active)])

        XCTAssertEqual(win.frame, originalFrame)
        XCTAssertEqual(other.frame, pulledBackFrame)
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

        desktop.place(batch.map { (windowId: $0.id, placement: .storage) })

        XCTAssertEqual(Set(batch.map(\.frame)), [nubFrame(size: originalFrame.size)])
    }

    func testPlaceKeepsTheWindowsOfOneApplicationOnOneThread() {
        let batch = (1...8).map { addWindow(CGWindowID($0) * 10, frame: originalFrame, pid: 42) }

        desktop.place(batch.map { (windowId: $0.id, placement: .storage) })

        XCTAssertEqual(Set(batch.compactMap(\.positionSetThread)).count, 1)
    }

    func testFocusReportsWhetherTheWindowWasStillThere() {
        XCTAssertTrue(desktop.focus(100))
        XCTAssertEqual(win.focusCount, 1)

        XCTAssertFalse(desktop.focus(200))
    }

    func testRestoreAllBringsEveryParkedWindowBack() {
        let other = addWindow(200, frame: CGRect(x: 300, y: 200, width: 400, height: 300))
        let onScreen = addWindow(300, frame: CGRect(x: 50, y: 50, width: 200, height: 200))
        desktop.place(100, at: .storage)
        desktop.place(200, at: .storage)

        desktop.restoreAll()

        XCTAssertEqual(win.frame, originalFrame)
        XCTAssertEqual(other.frame, CGRect(x: 300, y: 200, width: 400, height: 300))
        XCTAssertEqual(desktop.placement(of: 100), .active)
        XCTAssertEqual(desktop.placement(of: 200), .active)
        XCTAssertEqual(onScreen.positionSetCount, 0)
    }

    func testForgetClearsHiddenState() {
        desktop.place(100, at: .storage)
        desktop.forget(100)

        XCTAssertEqual(desktop.placement(of: 100), .active)
    }

    func testRecoverUnparksWindowsStuckInHiddenCorner() {
        let stuck = addWindow(200, frame: CGRect(x: 1791, y: 100, width: 800, height: 600))

        _ = desktop.recover([stuck.snapshot(), win.snapshot()])

        XCTAssertEqual(stuck.positionSetCount, 1)
        XCTAssertFalse(hiddenEdge.holds(stuck.frame))
        XCTAssertEqual(win.positionSetCount, 0)
    }

    func testRecoverShrinksAWindowLargerThanTheVisibleFrame() {
        let stuck = addWindow(200, frame: CGRect(x: 1791, y: 100, width: 3000, height: 600))

        _ = desktop.recover([stuck.snapshot()])

        XCTAssertEqual(stuck.sizeSetCount, 1)
        XCTAssertEqual(stuck.frame.width, StubScreen.standard.visibleFrame.width)
    }

    func testStartWatchingForManualNavigationFiresOnHiddenWindowFocus() {
        focusedWindowId = 100
        var received: [CGWindowID] = []

        desktop.startWatching { received.append($0) }
        desktop.place(100, at: .storage)
        center.postNativeSpaceChange()

        XCTAssertEqual(received, [100])
    }

    func testStartWatchingForManualNavigationIgnoresVisibleWindowFocus() {
        focusedWindowId = 100
        var received: [CGWindowID] = []

        desktop.startWatching { received.append($0) }
        center.postNativeSpaceChange()

        XCTAssertEqual(received, [])
    }

    func testNativeSpaceChangeParksStoredWindowsPulledBackOnScreenWithoutAnimations() {
        desktop.startWatching { _ in }
        desktop.place(100, at: .storage)
        win.moveTo(pulledBackFrame)
        center.postNativeSpaceChange()

        XCTAssertEqual(win.frame, nubFrame(size: originalFrame.size))
        XCTAssertEqual(win.animatedWriteCount, 0)

        desktop.place(100, at: .active)

        XCTAssertEqual(win.frame, originalFrame)
    }

    func testNativeSpaceChangeLeavesWindowsAtTheHiddenEdgeAlone() {
        desktop.startWatching { _ in }
        desktop.place(100, at: .storage)
        center.postNativeSpaceChange()

        XCTAssertEqual(win.positionSetCount, 1)
    }

    func testNativeSpaceChangeToAHiddenWindowLeavesItForTheCallback() {
        focusedWindowId = 100

        desktop.startWatching { _ in }
        desktop.place(100, at: .storage)
        win.moveTo(pulledBackFrame)
        center.postNativeSpaceChange()

        XCTAssertEqual(win.frame, pulledBackFrame)
    }

    func testStartWatchingForManualNavigationReplacesPreviousSubscription() {
        focusedWindowId = 100
        var first: [CGWindowID] = []
        var second: [CGWindowID] = []

        desktop.startWatching { first.append($0) }
        desktop.startWatching { second.append($0) }
        desktop.place(100, at: .storage)
        center.postNativeSpaceChange()

        XCTAssertEqual(first, [])
        XCTAssertEqual(second, [100])
    }
}
