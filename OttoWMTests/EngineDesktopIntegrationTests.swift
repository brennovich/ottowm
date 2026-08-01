import AppKit
import XCTest

final class EngineDesktopIntegrationTests: XCTestCase {
    private var windows: [CGWindowID: StubWindow] = [:]
    private var focused: StubWindow?
    private var nativeSpaceWindowIds: Set<CGWindowID>?
    private var snapshotCount = 0
    private let center = NotificationCenter()

    private lazy var onScreenWindows = OperationCache { [weak self] () -> Set<CGWindowID> in
        guard let self else { return [] }
        self.snapshotCount += 1
        return self.nativeSpaceWindowIds ?? Set(self.windows.keys)
    }

    private lazy var desktop: OffscreenParkingDesktop = OffscreenParkingDesktop(
        screen: StubScreen.standard,
        window: { [weak self] in self?.windows[$0] },
        onScreenWindowIds: { [weak self] in self?.onScreenWindows.value() ?? [] },
        managedWindowIds: { [weak self] in self?.engine.managedWindowIds ?? [] },
        focusedWindowId: { [weak self] in self?.focused?.id },
        notificationCenter: center
    )

    private lazy var engine: Engine = Engine(
        desktop: desktop,
        window: { [weak self] in self?.windows[$0] },
        focusedWindow: OperationCache { [weak self] in self?.focused?.snapshot() },
        onScreenWindows: onScreenWindows
    )

    private func addWindow(_ id: CGWindowID, frame: CGRect, isMinimized: Bool = false) -> StubWindow {
        let win = StubWindow(id: id, frame: frame, isMinimized: isMinimized)
        windows[id] = win
        return win
    }

    private func start() {
        engine.start(windows: windows.values.map { $0.snapshot() })
    }

    private func postNativeSpaceChange() {
        center.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
    }

    private func nubFrame(size: CGSize) -> CGRect {
        CGRect(origin: CGPoint(x: 1791, y: 1119), size: size)
    }

    func testSwitchRoundTripRestoresExactFrames() {
        let frame1 = CGRect(x: 100, y: 100, width: 800, height: 600)
        let frame2 = CGRect(x: 300, y: 200, width: 640, height: 480)
        let win1 = addWindow(100, frame: frame1)
        let win2 = addWindow(200, frame: frame2)
        focused = win1
        start()

        engine.moveWindowToWorkspace(win2.snapshot(), 2)

        XCTAssertEqual(win2.frame, nubFrame(size: frame2.size))

        engine.switchToWorkspace(2)

        XCTAssertEqual(win1.frame, nubFrame(size: frame1.size))
        XCTAssertEqual(win2.frame, frame2)

        focused = win2
        engine.handle(.focused(win2.snapshot()))
        engine.switchToWorkspace(1)

        XCTAssertEqual(win1.frame, frame1)
        XCTAssertEqual(win2.frame, nubFrame(size: frame2.size))
    }

    func testNativeSpaceChangeWithHiddenWindowFocusedSwitchesToItsWorkspace() {
        let frame1 = CGRect(x: 100, y: 100, width: 800, height: 600)
        let frame2 = CGRect(x: 300, y: 200, width: 640, height: 480)
        let win1 = addWindow(100, frame: frame1)
        let win2 = addWindow(200, frame: frame2)
        focused = win1
        start()
        engine.moveWindowToWorkspace(win2.snapshot(), 2)

        focused = win2
        postNativeSpaceChange()

        XCTAssertEqual(engine.currentWorkspace, 2)
        XCTAssertEqual(win2.frame, frame2)
        XCTAssertEqual(win1.frame, nubFrame(size: frame1.size))
    }

    func testReturnToDesktopSuppressesFollowUpManualNavigation() {
        let frame1 = CGRect(x: 100, y: 100, width: 800, height: 600)
        let win1 = addWindow(100, frame: frame1)
        focused = win1
        start()

        nativeSpaceWindowIds = []
        engine.switchToWorkspace(3)

        XCTAssertEqual(win1.focusCount, 1)
        XCTAssertEqual(win1.frame, nubFrame(size: frame1.size))

        nativeSpaceWindowIds = nil
        engine.handle(.focused(win1.snapshot()))

        XCTAssertEqual(engine.currentWorkspace, 3)
        XCTAssertEqual(win1.frame, nubFrame(size: frame1.size))
    }

    func testDestroyedHiddenWindowIdRecycledIsNotRestoredToStaleFrame() {
        let frame1 = CGRect(x: 50, y: 50, width: 400, height: 300)
        let staleFrame = CGRect(x: 100, y: 100, width: 800, height: 600)
        let win1 = addWindow(100, frame: frame1)
        let oldWin = addWindow(700, frame: staleFrame)
        focused = win1
        start()
        engine.moveWindowToWorkspace(oldWin.snapshot(), 2)

        windows[700] = nil
        engine.handle(.destroyed(700))

        XCTAssertEqual(desktop.placement(of: 700), .active)

        let recycledFrame = CGRect(x: 20, y: 30, width: 500, height: 400)
        let newWin = addWindow(700, frame: recycledFrame)
        engine.handle(.created(newWin.snapshot()))

        engine.switchToWorkspace(2)
        engine.switchToWorkspace(1)

        XCTAssertEqual(newWin.frame, recycledFrame)
        XCTAssertEqual(win1.frame, frame1)
    }

    func testClosingWorkspaceGuardIgnoresNativeSpaceChange() {
        let frame1 = CGRect(x: 100, y: 100, width: 800, height: 600)
        let frame2 = CGRect(x: 300, y: 200, width: 640, height: 480)
        _ = addWindow(100, frame: frame1)
        let win2 = addWindow(200, frame: frame2)
        focused = windows[100]
        start()
        engine.moveWindowToWorkspace(win2.snapshot(), 2)

        windows[100] = nil
        focused = win2
        postNativeSpaceChange()

        XCTAssertEqual(engine.currentWorkspace, 1)
        XCTAssertEqual(win2.frame, nubFrame(size: frame2.size))
    }

    func testSwitchTakesASingleWindowListSnapshot() {
        let win1 = addWindow(100, frame: CGRect(x: 100, y: 100, width: 800, height: 600))
        let win2 = addWindow(200, frame: CGRect(x: 300, y: 200, width: 640, height: 480))
        focused = win1
        start()
        engine.moveWindowToWorkspace(win2.snapshot(), 2)
        snapshotCount = 0

        engine.switchToWorkspace(2)

        XCTAssertEqual(snapshotCount, 1)
    }

    func testSwitchFromAFullScreenWindowComesBackToTheDesktop() {
        let frame1 = CGRect(x: 100, y: 100, width: 800, height: 600)
        let frame2 = CGRect(x: 300, y: 200, width: 640, height: 480)
        let win1 = addWindow(100, frame: frame1)
        let win2 = addWindow(200, frame: frame2)
        focused = win1
        start()

        win2.isFullScreen = true
        focused = win2
        nativeSpaceWindowIds = [200]
        engine.switchToWorkspace(1)

        XCTAssertEqual(engine.managedWindowIds, [100])
        XCTAssertEqual(win1.focusCount, 1)
        XCTAssertEqual(win2.frame, frame2)
    }

    func testMinimizedWindowIsLeftInPlaceAcrossSwitches() {
        let frame1 = CGRect(x: 100, y: 100, width: 800, height: 600)
        let minimizedFrame = CGRect(x: 300, y: 200, width: 640, height: 480)
        let win1 = addWindow(100, frame: frame1)
        let minimized = addWindow(300, frame: minimizedFrame, isMinimized: true)
        focused = win1
        start()

        engine.switchToWorkspace(2)
        engine.switchToWorkspace(1)

        XCTAssertEqual(minimized.frameSetCount, 0)
        XCTAssertEqual(minimized.frame, minimizedFrame)
        XCTAssertEqual(win1.frame, frame1)
    }
}
