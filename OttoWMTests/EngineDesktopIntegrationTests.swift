import CoreGraphics
import XCTest

final class EngineDesktopIntegrationTests: XCTestCase {
    private let frame1 = CGRect(x: 100, y: 100, width: 800, height: 600)
    private let frame2 = CGRect(x: 300, y: 200, width: 640, height: 480)
    private var windows: [CGWindowID: StubWindow] = [:]
    private var focused: StubWindow?
    private var nativeSpaceWindowIds: Set<CGWindowID>?
    private var snapshotCount = 0
    private let center = NotificationCenter()
    private lazy var workspaces = Workspaces(tabCount: { [weak self] id in self?.windows[id]?.tabCount() ?? 1 })
    private let hiddenEdge = HiddenEdge(screen: StubScreen.standard)

    private lazy var onScreenWindows = OperationCache { [weak self] () -> [CGWindowID: CGRect] in
        guard let self else { return [:] }
        self.snapshotCount += 1
        let ids = self.nativeSpaceWindowIds ?? Set(self.windows.keys)
        return ids.reduce(into: [CGWindowID: CGRect]()) { $0[$1] = self.windows[$1]?.frame ?? .zero }
    }

    private let parkedWindows = ParkedWindows()

    private lazy var desktop: OffscreenParkingDesktop = OffscreenParkingDesktop(
        screen: StubScreen.standard,
        window: { [weak self] in self?.windows[$0] },
        notificationCenter: center
    )

    private lazy var engine: Engine = Engine(
        desktop: desktop,
        windowSystem: WindowSystem(
            focusedWindow: OperationCache { [weak self] in self?.focused?.snapshot() },
            onScreenWindows: onScreenWindows,
            window: { [weak self] in self?.windows[$0] }
        ),
        workspaces: workspaces,
        parkedWindows: parkedWindows
    )

    private func addWindow(_ id: CGWindowID, frame: CGRect, isMinimized: Bool = false) -> StubWindow {
        let win = StubWindow(id: id, frame: frame, isMinimized: isMinimized)
        windows[id] = win
        return win
    }

    private func start() {
        engine.start(windows: windows.values.map { $0.snapshot() })
    }

    private func moveFocusedWindow(_ window: StubWindow, to workspace: Int) {
        focused = window
        engine.moveFocusedWindow(toWorkspace: workspace)
    }

    private func minimizeAndRestore(_ window: StubWindow) {
        window.isMinimized = true
        engine.handle(.minimized(window.id))
        window.isMinimized = false
    }

    func testSwitchRoundTripRestoresExactFrames() {
        let win1 = addWindow(100, frame: frame1)
        let win2 = addWindow(200, frame: frame2)
        start()

        moveFocusedWindow(win2, to: 2)

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
        let win1 = addWindow(100, frame: frame1)
        let win2 = addWindow(200, frame: frame2)
        start()
        moveFocusedWindow(win2, to: 2)

        focused = win2
        center.postNativeSpaceChange()

        XCTAssertEqual(workspaces.current, 2)
        XCTAssertEqual(win2.frame, frame2)
        XCTAssertEqual(win1.frame, nubFrame(size: frame1.size))
    }

    func testNativeSpaceChangeParksAgainTheWindowsItPulledBackOnScreen() {
        let win1 = addWindow(100, frame: frame1)
        let win2 = addWindow(200, frame: frame2)
        focused = win1
        start()
        moveFocusedWindow(win2, to: 2)

        win2.moveTo(frame2)
        focused = win1
        center.postNativeSpaceChange()

        XCTAssertEqual(win2.frame, nubFrame(size: frame2.size))
        XCTAssertEqual(workspaces.current, 1)
    }

    func testReturnToDesktopSuppressesFollowUpManualNavigation() {
        let win1 = addWindow(100, frame: frame1)
        focused = win1
        start()

        nativeSpaceWindowIds = []
        engine.switchToWorkspace(3)

        XCTAssertEqual(win1.focusCount, 1)
        XCTAssertEqual(win1.frame, nubFrame(size: frame1.size))

        nativeSpaceWindowIds = nil
        engine.handle(.focused(win1.snapshot()))

        XCTAssertEqual(workspaces.current, 3)
        XCTAssertEqual(win1.frame, nubFrame(size: frame1.size))
    }

    func testDestroyedHiddenWindowIdRecycledIsNotRestoredToStaleFrame() {
        let win1 = addWindow(100, frame: frame1)
        let oldWin = addWindow(700, frame: frame2)
        start()
        moveFocusedWindow(oldWin, to: 2)

        windows[700] = nil
        engine.handle(.destroyed(700))

        XCTAssertEqual(parkedWindows.placement(of: 700), .active)

        let recycledFrame = CGRect(x: 20, y: 30, width: 500, height: 400)
        let newWin = addWindow(700, frame: recycledFrame)
        engine.handle(.created(newWin.snapshot()))

        engine.switchToWorkspace(2)
        engine.switchToWorkspace(1)

        XCTAssertEqual(newWin.frame, recycledFrame)
        XCTAssertEqual(win1.frame, frame1)
    }

    func testClosingWorkspaceGuardIgnoresNativeSpaceChange() {
        _ = addWindow(100, frame: frame1)
        let win2 = addWindow(200, frame: frame2)
        start()
        moveFocusedWindow(win2, to: 2)

        windows[100] = nil
        focused = win2
        center.postNativeSpaceChange()

        XCTAssertEqual(workspaces.current, 1)
        XCTAssertEqual(win2.frame, nubFrame(size: frame2.size))
    }

    func testSwitchTakesASingleOnScreenWindowsSnapshot() {
        _ = addWindow(100, frame: frame1)
        let win2 = addWindow(200, frame: frame2)
        start()
        moveFocusedWindow(win2, to: 2)
        snapshotCount = 0

        engine.switchToWorkspace(2)

        XCTAssertEqual(snapshotCount, 1)
    }

    func testSwitchFromAFullScreenWindowComesBackToTheDesktop() {
        let win1 = addWindow(100, frame: frame1)
        let win2 = addWindow(200, frame: frame2)
        focused = win1
        start()

        win2.isFullScreen = true
        focused = win2
        nativeSpaceWindowIds = [200]
        engine.switchToWorkspace(1)

        XCTAssertEqual(workspaces.allWindowIds, [100])
        XCTAssertEqual(win1.focusCount, 1)
        XCTAssertEqual(win2.frame, frame2)
    }

    func testWindowOnAnotherNativeSpaceIsNeverParked() {
        let win1 = addWindow(100, frame: frame1)
        start()
        moveFocusedWindow(win1, to: 2)

        let foreign = addWindow(200, frame: frame2)
        focused = nil
        nativeSpaceWindowIds = [200]
        engine.handle(.created(foreign.snapshot()))

        nativeSpaceWindowIds = nil
        engine.switchToWorkspace(2)
        engine.switchToWorkspace(1)

        XCTAssertNil(workspaces.workspace(for: 200))
        XCTAssertEqual(foreign.frame, frame2)
    }

    func testWindowMinimizedWhileParkedIsRecoveredWhenItComesBack() {
        _ = addWindow(100, frame: frame1)
        let win2 = addWindow(200, frame: frame2)
        start()
        moveFocusedWindow(win2, to: 2)

        minimizeAndRestore(win2)
        engine.handle(.unminimized(win2.snapshot()))

        XCTAssertFalse(hiddenEdge.holds(win2.frame))
        XCTAssertTrue(workspaces.allWindowIds.contains(200))
    }

    func testWindowReadmittedWhileStrandedAtTheHiddenEdgeIsBroughtBack() {
        let win1 = addWindow(100, frame: frame1)
        let win2 = addWindow(200, frame: frame2)
        focused = win1
        start()
        moveFocusedWindow(win2, to: 2)

        minimizeAndRestore(win2)

        focused = win2
        engine.handle(.focused(win2.snapshot()))

        XCTAssertEqual(workspaces.workspace(for: 200), 1)
        XCTAssertFalse(hiddenEdge.holds(win2.frame))
    }

    func testAWindowRecoveredFromTheHiddenEdgeKeepsItsNewFrameAcrossSwitches() {
        let win1 = addWindow(100, frame: frame1)
        let win2 = addWindow(200, frame: frame2)
        focused = win1
        start()
        moveFocusedWindow(win2, to: 2)

        minimizeAndRestore(win2)
        focused = win2
        engine.handle(.focused(win2.snapshot()))
        let recovered = win2.frame

        focused = win1
        engine.switchToWorkspace(2)
        engine.switchToWorkspace(1)

        XCTAssertEqual(win2.frame, recovered)
        XCTAssertEqual(win1.frame, frame1)
    }

    func testMinimizedWindowIsLeftInPlaceAcrossSwitches() {
        let win1 = addWindow(100, frame: frame1)
        let minimized = addWindow(300, frame: frame2, isMinimized: true)
        focused = win1
        start()

        engine.switchToWorkspace(2)
        engine.switchToWorkspace(1)

        XCTAssertEqual(minimized.positionSetCount, 0)
        XCTAssertEqual(minimized.frame, frame2)
        XCTAssertEqual(win1.frame, frame1)
    }

    func testSwitchingReadsNoTabCounts() {
        let win1 = addWindow(100, frame: frame1)
        let win2 = addWindow(200, frame: frame2)
        focused = win1
        start()
        moveFocusedWindow(win2, to: 2)

        let before = windows.values.reduce(0) { $0 + $1.tabCountReadCount }
        focused = win1
        engine.switchToWorkspace(2)
        engine.switchToWorkspace(1)

        XCTAssertEqual(windows.values.reduce(0) { $0 + $1.tabCountReadCount }, before)
    }

    func testFocusFallsToALiveWindowWhenTheRememberedOneIsGone() {
        let win1 = addWindow(100, frame: frame1)
        let live = addWindow(200, frame: frame2)
        let vanished = addWindow(300, frame: frame2)
        focused = win1
        start()
        moveFocusedWindow(live, to: 2)
        moveFocusedWindow(vanished, to: 2)

        windows[300] = nil
        focused = win1
        engine.switchToWorkspace(2)

        XCTAssertEqual(live.focusCount, 1)
        XCTAssertNil(workspaces.workspace(for: 300))
    }
}
