import AppKit
import XCTest

private let originalFrame = CGRect(x: 100, y: 100, width: 800, height: 600)

final class OffscreenParkingDesktopTests: XCTestCase {
    private let win = StubWindow(id: 100, frame: originalFrame)
    private var focusedWindowId: CGWindowID?
    private var lookupCount = 0
    private let center = NotificationCenter()

    private lazy var windows = [win.id: win]

    private lazy var desktop = OffscreenParkingDesktop(
        screen: StubScreen.standard,
        window: { [weak self] id in
            self?.lookupCount += 1
            return self?.windows[id]
        },
        focusedWindowId: { [weak self] in self?.focusedWindowId },
        notificationCenter: center
    )

    @discardableResult
    private func addWindow(_ id: CGWindowID, frame: CGRect) -> StubWindow {
        let window = StubWindow(id: id, frame: frame)
        windows[id] = window
        return window
    }

    func testPlaceCapturesFrameAndHidesThenRestores() {
        XCTAssertEqual(desktop.placement(of: 100), .active)

        desktop.place(100, .storage)

        XCTAssertEqual(win.frame, nubFrame(size: originalFrame.size))
        XCTAssertEqual(desktop.placement(of: 100), .storage)

        desktop.place(100, .active)

        XCTAssertEqual(win.frame, originalFrame)
        XCTAssertEqual(desktop.placement(of: 100), .active)
    }

    func testPlaceIsIdempotentAndReadsTheWindowOncePerMove() {
        desktop.place(100, .storage)
        desktop.place(100, .storage)

        XCTAssertEqual(win.frameSetCount, 1)
        XCTAssertEqual(lookupCount, 1)

        desktop.place(100, .active)
        desktop.place(100, .active)

        XCTAssertEqual(win.frameSetCount, 2)
        XCTAssertEqual(win.frame, originalFrame)
        XCTAssertEqual(lookupCount, 2)
        XCTAssertEqual(win.movableFrameCount, 2)
    }

    func testPlaceSkipsMinimizedWindows() {
        win.isMinimized = true

        desktop.place(100, .storage)

        XCTAssertEqual(win.frameSetCount, 0)
        XCTAssertEqual(desktop.placement(of: 100), .active)
    }

    func testPlaceHandlesMissingWindow() {
        desktop.place(999, .storage)

        XCTAssertEqual(desktop.placement(of: 999), .active)
    }

    func testFocusReportsWhetherTheWindowWasStillThere() {
        XCTAssertTrue(desktop.focus(100))
        XCTAssertEqual(win.focusCount, 1)

        XCTAssertFalse(desktop.focus(200))
    }

    func testForgetClearsHiddenState() {
        desktop.place(100, .storage)
        desktop.forget(100)

        XCTAssertEqual(desktop.placement(of: 100), .active)
    }

    func testRecoverUnparksWindowsStuckInHiddenCorner() {
        let stuck = addWindow(200, frame: CGRect(x: 1791, y: 100, width: 800, height: 600))

        desktop.recover(windows: [stuck.snapshot(), win.snapshot()])

        XCTAssertEqual(stuck.frameSetCount, 1)
        XCTAssertFalse(OffscreenParkingDesktop.HiddenEdge(screen: StubScreen.standard).holds(stuck.frame))
        XCTAssertEqual(win.frameSetCount, 0)
    }

    func testStartWatchingForManualNavigationFiresOnHiddenWindowFocus() {
        focusedWindowId = 100
        var received: [CGWindowID] = []

        desktop.startWatchingForManualNavigation { received.append($0) }
        desktop.place(100, .storage)
        center.postNativeSpaceChange()

        XCTAssertEqual(received, [100])
    }

    func testStartWatchingForManualNavigationIgnoresVisibleWindowFocus() {
        focusedWindowId = 100
        var received: [CGWindowID] = []

        desktop.startWatchingForManualNavigation { received.append($0) }
        center.postNativeSpaceChange()

        XCTAssertEqual(received, [])
    }

    func testNativeSpaceChangeParksStoredWindowsPulledBackOnScreen() {
        desktop.startWatchingForManualNavigation { _ in }
        desktop.place(100, .storage)
        win.setFrame(CGRect(x: 200, y: 300, width: 800, height: 600))
        center.postNativeSpaceChange()

        XCTAssertEqual(win.frame, nubFrame(size: originalFrame.size))

        desktop.place(100, .active)

        XCTAssertEqual(win.frame, originalFrame)
    }

    func testNativeSpaceChangeLeavesWindowsAtTheHiddenEdgeAlone() {
        desktop.startWatchingForManualNavigation { _ in }
        desktop.place(100, .storage)
        center.postNativeSpaceChange()

        XCTAssertEqual(win.frameSetCount, 1)
    }

    func testNativeSpaceChangeToAHiddenWindowLeavesItForTheCallback() {
        focusedWindowId = 100

        desktop.startWatchingForManualNavigation { _ in }
        desktop.place(100, .storage)
        win.setFrame(CGRect(x: 200, y: 300, width: 800, height: 600))
        center.postNativeSpaceChange()

        XCTAssertEqual(win.frame, CGRect(x: 200, y: 300, width: 800, height: 600))
    }

    func testStartWatchingForManualNavigationReplacesPreviousSubscription() {
        focusedWindowId = 100
        var first: [CGWindowID] = []
        var second: [CGWindowID] = []

        desktop.startWatchingForManualNavigation { first.append($0) }
        desktop.startWatchingForManualNavigation { second.append($0) }
        desktop.place(100, .storage)
        center.postNativeSpaceChange()

        XCTAssertEqual(first, [])
        XCTAssertEqual(second, [100])
    }
}
