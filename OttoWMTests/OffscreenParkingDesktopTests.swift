import AppKit
import XCTest

private let testScreen: Screen = StubScreen.standard

private func makeDesktop(
    _ windows: [StubWindow] = [],
    onScreen: @escaping () -> Set<CGWindowID> = { [] },
    managed: @escaping () -> Set<CGWindowID> = { [] },
    focusedWindowId: @escaping () -> CGWindowID? = { nil },
    center: NotificationCenter = NotificationCenter()
) -> OffscreenParkingDesktop {
    let registry = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
    return OffscreenParkingDesktop(
        screen: testScreen,
        window: { registry[$0] },
        onScreenWindowIds: onScreen,
        managedWindowIds: managed,
        focusedWindowId: focusedWindowId,
        notificationCenter: center
    )
}

final class OffscreenParkingDesktopTests: XCTestCase {
    private let originalFrame = CGRect(x: 100, y: 100, width: 800, height: 600)

    func testPlaceCapturesFrameAndHidesThenRestores() {
        let win = StubWindow(id: 100, frame: originalFrame)
        let desktop = makeDesktop([win])

        desktop.place(100, .storage)

        XCTAssertEqual(win.frameSetCount, 1)
        XCTAssertEqual(win.frame, CGRect(x: 1791, y: 1119, width: 800, height: 600))

        desktop.place(100, .active)

        XCTAssertEqual(win.frameSetCount, 2)
        XCTAssertEqual(win.frame, originalFrame)
    }

    func testPlaceIsIdempotentOnDoubleHide() {
        let win = StubWindow(id: 100, frame: originalFrame)
        let desktop = makeDesktop([win])

        desktop.place(100, .storage)
        desktop.place(100, .storage)

        XCTAssertEqual(win.frameSetCount, 1)

        desktop.place(100, .active)

        XCTAssertEqual(win.frameSetCount, 2)
        XCTAssertEqual(win.frame, originalFrame)
    }

    func testPlaceIsIdempotentOnDoubleShow() {
        let win = StubWindow(id: 100, frame: originalFrame)
        let desktop = makeDesktop([win])

        desktop.place(100, .storage)
        desktop.place(100, .active)
        desktop.place(100, .active)

        XCTAssertEqual(win.frameSetCount, 2)
    }

    func testPlaceSkipsLookupOnNoOpMoves() {
        let win = StubWindow(id: 100, frame: originalFrame)
        var lookupCount = 0
        let desktop = OffscreenParkingDesktop(
            screen: testScreen,
            window: { id in
                lookupCount += 1
                return id == win.id ? win : nil
            },
            onScreenWindowIds: { [] },
            managedWindowIds: { [] },
            focusedWindowId: { nil },
            notificationCenter: NotificationCenter()
        )

        desktop.place(100, .storage)
        desktop.place(100, .storage)

        XCTAssertEqual(lookupCount, 1)

        desktop.place(100, .active)
        desktop.place(100, .active)

        XCTAssertEqual(lookupCount, 2)
    }

    func testPlaceReadsWindowStateOnce() {
        let win = StubWindow(id: 100, frame: originalFrame)
        let desktop = makeDesktop([win])

        desktop.place(100, .storage)
        desktop.place(100, .active)

        XCTAssertEqual(win.movableFrameCount, 2)
    }

    func testPlaceSkipsMinimizedWindows() {
        let win = StubWindow(id: 100, frame: originalFrame, isMinimized: true)
        let desktop = makeDesktop([win])

        desktop.place(100, .storage)

        XCTAssertEqual(win.frameSetCount, 0)
        XCTAssertEqual(desktop.placement(of: 100), .active)
    }

    func testPlaceHandlesMissingWindow() {
        let desktop = makeDesktop([])

        desktop.place(999, .storage)

        XCTAssertEqual(desktop.placement(of: 999), .active)
    }

    func testPlacementReflectsHiddenState() {
        let win = StubWindow(id: 100, frame: originalFrame)
        let desktop = makeDesktop([win])

        XCTAssertEqual(desktop.placement(of: 100), .active)

        desktop.place(100, .storage)
        XCTAssertEqual(desktop.placement(of: 100), .storage)

        desktop.place(100, .active)
        XCTAssertEqual(desktop.placement(of: 100), .active)
    }

    func testForgetClearsHiddenState() {
        let win = StubWindow(id: 100, frame: originalFrame)
        let desktop = makeDesktop([win])

        desktop.place(100, .storage)
        desktop.forget(100)

        XCTAssertEqual(desktop.placement(of: 100), .active)
    }

    func testSetupForMainScreenRecoversWindowsStuckInHiddenCorner() {
        let stuck = StubWindow(id: 200, frame: CGRect(x: 1791, y: 100, width: 800, height: 600))
        let normal = StubWindow(id: 300, frame: originalFrame)
        let desktop = makeDesktop([stuck, normal])

        desktop.setupForMainScreen(windows: [stuck.snapshot(), normal.snapshot()])

        XCTAssertEqual(stuck.frameSetCount, 1)
        XCTAssertLessThan(stuck.frame.minX, testScreen.fullFrame.maxX - hiddenEdgeDetectionMargin)
        XCTAssertEqual(normal.frameSetCount, 0)
    }

    func testContainsReflectsOnScreenWindows() {
        let desktop = makeDesktop(onScreen: { [100] })

        XCTAssertTrue(desktop.contains(100))
        XCTAssertFalse(desktop.contains(200))
    }

    func testIsFrontmostReflectsManagedWindowsBeingOnScreen() {
        var onScreen: Set<CGWindowID> = [100]
        let desktop = makeDesktop(onScreen: { onScreen }, managed: { [100, 200] })

        XCTAssertTrue(desktop.isFrontmost())

        onScreen = [999]
        XCTAssertFalse(desktop.isFrontmost())
    }

    func testBringToFrontFocusesAManagedWindow() {
        let win = StubWindow(id: 100, frame: originalFrame)
        let desktop = makeDesktop([win], managed: { [100] })

        desktop.bringToFront()

        XCTAssertEqual(win.focusCount, 1)
    }

    func testBringToFrontIsNoOpWithoutManagedWindows() {
        let win = StubWindow(id: 100, frame: originalFrame)
        let desktop = makeDesktop([win], managed: { [] })

        desktop.bringToFront()

        XCTAssertEqual(win.focusCount, 0)
    }

    func testStartWatchingForManualNavigationFiresOnHiddenWindowFocus() {
        let win = StubWindow(id: 100, frame: originalFrame)
        let center = NotificationCenter()
        let desktop = makeDesktop([win], focusedWindowId: { win.id }, center: center)
        var received: [CGWindowID] = []

        desktop.startWatchingForManualNavigation { received.append($0) }
        desktop.place(100, .storage)
        center.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        XCTAssertEqual(received, [100])
    }

    func testStartWatchingForManualNavigationIgnoresVisibleWindowFocus() {
        let win = StubWindow(id: 100, frame: originalFrame)
        let center = NotificationCenter()
        let desktop = makeDesktop([win], focusedWindowId: { win.id }, center: center)
        var received: [CGWindowID] = []

        desktop.startWatchingForManualNavigation { received.append($0) }
        center.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        XCTAssertEqual(received, [])
    }

    func testStartWatchingForManualNavigationReplacesPreviousSubscription() {
        let win = StubWindow(id: 100, frame: originalFrame)
        let center = NotificationCenter()
        let desktop = makeDesktop([win], focusedWindowId: { win.id }, center: center)
        var first: [CGWindowID] = []
        var second: [CGWindowID] = []

        desktop.startWatchingForManualNavigation { first.append($0) }
        desktop.startWatchingForManualNavigation { second.append($0) }
        desktop.place(100, .storage)
        center.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        XCTAssertEqual(first, [])
        XCTAssertEqual(second, [100])
    }
}
