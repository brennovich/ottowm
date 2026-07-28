import AppKit
import XCTest

private let testScreen: Screen = StubScreen.standard

private func makeSpace(
    _ windows: [StubWindow] = [],
    onScreen: @escaping () -> Set<CGWindowID> = { [] },
    managed: @escaping () -> Set<CGWindowID> = { [] },
    focused: @escaping () -> (any Window)? = { nil },
    center: NotificationCenter = NotificationCenter()
) -> VirtualSpace {
    let registry = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
    return VirtualSpace(
        screen: testScreen,
        window: { registry[$0] },
        allWindows: { windows },
        onScreenWindowIds: onScreen,
        managedWindowIds: managed,
        focusedWindow: focused,
        notificationCenter: center
    )
}

final class VirtualSpaceTests: XCTestCase {
    private let originalFrame = CGRect(x: 100, y: 100, width: 800, height: 600)

    func testMoveWindowToSpaceCapturesFrameAndHidesThenRestores() {
        let win = StubWindow(id: 100, frame: originalFrame)
        let space = makeSpace([win])

        space.moveWindowToSpace(100, .storage)

        XCTAssertEqual(win.frameSetCount, 1)
        XCTAssertEqual(win.frame, CGRect(x: 1791, y: 1119, width: 800, height: 600))

        space.moveWindowToSpace(100, .active)

        XCTAssertEqual(win.frameSetCount, 2)
        XCTAssertEqual(win.frame, originalFrame)
    }

    func testMoveWindowToSpaceIsIdempotentOnDoubleHide() {
        let win = StubWindow(id: 100, frame: originalFrame)
        let space = makeSpace([win])

        space.moveWindowToSpace(100, .storage)
        space.moveWindowToSpace(100, .storage)

        XCTAssertEqual(win.frameSetCount, 1)

        space.moveWindowToSpace(100, .active)

        XCTAssertEqual(win.frameSetCount, 2)
        XCTAssertEqual(win.frame, originalFrame)
    }

    func testMoveWindowToSpaceIsIdempotentOnDoubleShow() {
        let win = StubWindow(id: 100, frame: originalFrame)
        let space = makeSpace([win])

        space.moveWindowToSpace(100, .storage)
        space.moveWindowToSpace(100, .active)
        space.moveWindowToSpace(100, .active)

        XCTAssertEqual(win.frameSetCount, 2)
    }

    func testMoveWindowToSpaceSkipsMinimizedWindows() {
        let win = StubWindow(id: 100, frame: originalFrame, isMinimized: true)
        let space = makeSpace([win])

        space.moveWindowToSpace(100, .storage)

        XCTAssertEqual(win.frameSetCount, 0)
        XCTAssertEqual(space.windowSpaces(100), .active)
    }

    func testMoveWindowToSpaceHandlesMissingWindow() {
        let space = makeSpace([])

        space.moveWindowToSpace(999, .storage)

        XCTAssertEqual(space.windowSpaces(999), .active)
    }

    func testWindowSpacesReflectsHiddenState() {
        let win = StubWindow(id: 100, frame: originalFrame)
        let space = makeSpace([win])

        XCTAssertEqual(space.windowSpaces(100), .active)

        space.moveWindowToSpace(100, .storage)
        XCTAssertEqual(space.windowSpaces(100), .storage)

        space.moveWindowToSpace(100, .active)
        XCTAssertEqual(space.windowSpaces(100), .active)
    }

    func testForgetWindowClearsHiddenState() {
        let win = StubWindow(id: 100, frame: originalFrame)
        let space = makeSpace([win])

        space.moveWindowToSpace(100, .storage)
        space.forgetWindow(100)

        XCTAssertEqual(space.windowSpaces(100), .active)
    }

    func testSetupForMainScreenRecoversWindowsStuckInHiddenCorner() {
        let stuck = StubWindow(id: 200, frame: CGRect(x: 1791, y: 100, width: 800, height: 600))
        let normal = StubWindow(id: 300, frame: originalFrame)
        let space = makeSpace([stuck, normal])

        space.setupForMainScreen()

        XCTAssertEqual(stuck.frameSetCount, 1)
        XCTAssertLessThan(stuck.frame.minX, testScreen.fullFrame.maxX - hiddenEdgeDetectionMargin)
        XCTAssertEqual(normal.frameSetCount, 0)
    }

    func testManagesWindowReflectsCurrentSpaceMembership() {
        let space = makeSpace(onScreen: { [100] })

        XCTAssertTrue(space.managesWindow(100))
        XCTAssertFalse(space.managesWindow(200))
    }

    func testIsOnManagedSpaceReflectsManagedWindowsBeingOnScreen() {
        var onScreen: Set<CGWindowID> = [100]
        let space = makeSpace(onScreen: { onScreen }, managed: { [100, 200] })

        XCTAssertTrue(space.isOnManagedSpace())

        onScreen = [999]
        XCTAssertFalse(space.isOnManagedSpace())
    }

    func testActivateManagedSpaceFocusesAManagedWindow() {
        let win = StubWindow(id: 100, frame: originalFrame)
        let space = makeSpace([win], managed: { [100] })

        space.activateManagedSpace()

        XCTAssertEqual(win.focusCount, 1)
    }

    func testActivateManagedSpaceIsNoOpWithoutManagedWindows() {
        let win = StubWindow(id: 100, frame: originalFrame)
        let space = makeSpace([win], managed: { [] })

        space.activateManagedSpace()

        XCTAssertEqual(win.focusCount, 0)
    }

    func testStartWatchingForManualNavigationFiresOnHiddenWindowFocus() {
        let win = StubWindow(id: 100, frame: originalFrame)
        let center = NotificationCenter()
        let space = makeSpace([win], focused: { win }, center: center)
        var received: [Placement] = []

        space.startWatchingForManualNavigation { received.append($0) }
        space.moveWindowToSpace(100, .storage)
        center.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        XCTAssertEqual(received, [.storage])
    }

    func testStartWatchingForManualNavigationIgnoresVisibleWindowFocus() {
        let win = StubWindow(id: 100, frame: originalFrame)
        let center = NotificationCenter()
        let space = makeSpace([win], focused: { win }, center: center)
        var received: [Placement] = []

        space.startWatchingForManualNavigation { received.append($0) }
        center.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        XCTAssertEqual(received, [])
    }

    func testStartWatchingForManualNavigationReplacesPreviousSubscription() {
        let win = StubWindow(id: 100, frame: originalFrame)
        let center = NotificationCenter()
        let space = makeSpace([win], focused: { win }, center: center)
        var first: [Placement] = []
        var second: [Placement] = []

        space.startWatchingForManualNavigation { first.append($0) }
        space.startWatchingForManualNavigation { second.append($0) }
        space.moveWindowToSpace(100, .storage)
        center.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        XCTAssertEqual(first, [])
        XCTAssertEqual(second, [.storage])
    }
}
