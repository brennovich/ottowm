import CoreGraphics
import XCTest

final class EngineDesktopIntegrationTests: XCTestCase {
    private let frame1 = CGRect(x: 100, y: 100, width: 800, height: 600)
    private let frame2 = CGRect(x: 300, y: 200, width: 640, height: 480)
    private var windows: [CGWindowID: StubWindow] = [:]
    private var focused: StubWindow?
    private let center = NotificationCenter()
    private let screens = StubScreen(main: .standard)
    private lazy var workspaces = Workspaces(
        tabGroups: TabGroups(
            tabCount: { [weak self] id in self?.windows[id]?.tabCount() ?? 1 },
            frame: { [weak self] id in self?.windows[id]?.movableFrame() }
        )
    )

    private lazy var onScreenWindows = OperationCache { [weak self] () -> [CGWindowID: CGRect] in
        guard let self else { return [:] }
        return self.windows.reduce(into: [CGWindowID: CGRect]()) { $0[$1.key] = $1.value.frame }
    }

    private lazy var desktop: OffscreenParkingDesktop = OffscreenParkingDesktop(
        screens: screens,
        window: { [weak self] in self?.windows[$0] },
        notificationCenter: center,
        screenNotificationCenter: center
    )

    private lazy var engine: Engine = Engine.system(
        desktop: desktop,
        windowSystem: WindowSystem(
            focusedWindow: OperationCache { [weak self] in self?.focused?.snapshot() },
            onScreenWindows: onScreenWindows,
            window: { [weak self] in self?.windows[$0] }
        ),
        workspaces: workspaces
    )

    private func addWindow(_ id: CGWindowID, frame: CGRect) -> StubWindow {
        let win = StubWindow(id: id, frame: frame)
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

    func testSwitchRoundTripRestoresExactFrames() {
        let win1 = addWindow(100, frame: frame1)
        let win2 = addWindow(200, frame: frame2)
        start()

        moveFocusedWindow(win2, to: 2)

        XCTAssertEqual(win2.frame, hiddenEdgeFrame(size: frame2.size))

        engine.switchToWorkspace(2)

        XCTAssertEqual(win1.frame, hiddenEdgeFrame(size: frame1.size))
        XCTAssertEqual(win2.frame, frame2)

        focused = win2
        engine.handle(.focused(win2.snapshot()))
        engine.switchToWorkspace(1)

        XCTAssertEqual(win1.frame, frame1)
        XCTAssertEqual(win2.frame, hiddenEdgeFrame(size: frame2.size))
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
        XCTAssertEqual(win1.frame, hiddenEdgeFrame(size: frame1.size))
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

        XCTAssertEqual(win2.frame, hiddenEdgeFrame(size: frame2.size))
        XCTAssertEqual(workspaces.current, 1)
    }

    func testADisplayRoundTripPutsEveryWindowBackWhereItWas() {
        let win1 = addWindow(100, frame: frame1)
        let win2 = addWindow(200, frame: frame2)
        start()
        moveFocusedWindow(win2, to: 2)
        let fit = Fit(from: Display.standard.visibleFrame, into: Display.external.visibleFrame)

        screens.main = .external
        center.postScreenParametersChange()

        XCTAssertEqual(win1.frame, fit.frame(frame1))
        XCTAssertEqual(win2.frame, hiddenEdgeFrame(size: frame2.size, on: .external))

        screens.main = .standard
        center.postScreenParametersChange()

        XCTAssertEqual(win1.frame, frame1)
        XCTAssertEqual(win2.frame, hiddenEdgeFrame(size: frame2.size))

        engine.switchToWorkspace(2)

        XCTAssertEqual(win2.frame, frame2)
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
}
