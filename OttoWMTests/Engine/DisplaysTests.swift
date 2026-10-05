import CoreGraphics
import XCTest

final class DisplaysTests: XCTestCase {
    private let onStandard = CGRect(x: 100, y: 100, width: 800, height: 600)
    private let onAirPlay = CGRect(x: 2000, y: 100, width: 800, height: 600)
    private let airPlayOnTheLeft = Display(
        id: Display.airPlay.id,
        fullFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: -1920, y: 25, width: 1920, height: 1055)
    )
    private let newPrimary = Display(
        id: DisplayID(rawValue: "new-primary"),
        fullFrame: CGRect(x: -2560, y: 0, width: 2560, height: 1440),
        visibleFrame: CGRect(x: -2560, y: 25, width: 2560, height: 1415)
    )
    private var windows: [CGWindowID: StubWindow] = [:]
    private var focused: StubWindow?
    private var focusedReadCount = 0
    private var onScreenReadCount = 0
    private var connected: [Display] = [.standard, .airPlay]
    private var activeDisplay: DisplayID?
    private var screenIsLocked = false
    private var screenParametersChanged: (() -> Void)?
    private var workspaces: [DisplayID: Workspaces] = [:]
    private var desktops: [DisplayID: StubDesktop] = [:]
    private var written: [[SavedState]] = []
    private let layouts = DisplayLayouts()

    private lazy var windowSystem = WindowSystem(
        focusedWindow: OperationCache { [weak self] in
            guard let self else { return nil }
            self.focusedReadCount += 1
            return self.focused?.snapshot()
        },
        onScreenWindows: OperationCache { [weak self] in
            guard let self else { return [:] }
            self.onScreenReadCount += 1
            return self.windows.mapValues(\.frame)
        },
        window: { [weak self] id in self?.windows[id] }
    )

    private lazy var displays = makeDisplays()

    private func makeDisplays() -> Displays {
        workspaces = [:]
        desktops = [:]
        return Displays(
            screens: Screens(
                all: { [weak self] in self?.connected ?? [] },
                active: { [weak self] in self?.activeDisplay },
                startWatching: { [weak self] in self?.screenParametersChanged = $0 }
            ),
            windowSystem: windowSystem,
            screenIsLocked: { [weak self] in self?.screenIsLocked ?? false },
            write: { [weak self] in self?.written.append($0) },
            engine: { [weak self, layouts] display, windowSystem, save in
                let desktop = StubDesktop(window: { [weak self] id in self?.windows[id] })
                desktop.display = display
                let workspaces = Workspaces(
                    tabGroups: TabGroups(tabCount: { _ in 1 }, frame: { [weak self] id in self?.windows[id]?.movableFrame() })
                )
                self?.desktops[display.id] = desktop
                self?.workspaces[display.id] = workspaces
                let engine = Engine.system(
                    desktop: desktop,
                    windowSystem: windowSystem,
                    workspaces: workspaces,
                    layouts: layouts,
                    scheduleRetry: { _, _ in },
                    save: save
                )
                return (workspaces, desktop, engine)
            }
        )
    }

    @discardableResult
    private func add(_ id: CGWindowID, frame: CGRect) -> StubWindow {
        let window = StubWindow(id: id, frame: frame)
        windows[id] = window
        return window
    }

    private func section(on display: Display, current: Int, _ windowId: CGWindowID) -> SavedState {
        var workspace = Workspace()
        workspace.add(windowId)
        return SavedState(
            display: display,
            workspaces: Workspaces.Record(current: current, workspaces: [current: workspace]),
            parkedWindows: [:],
            originalFrames: [:],
            displayLayouts: [:]
        )
    }

    func testAnEngineSeesOnlyTheWindowsOnItsDisplay() {
        displays.handle(.created(add(100, frame: onStandard).snapshot()))
        focused = add(200, frame: onAirPlay)

        displays.handle(.destroyed(100))

        XCTAssertEqual(workspaces[Display.standard.id]?.membership(of: 200), .unassigned)
    }

    func testAnActionGoesToTheDisplayOfTheFocusedWindowElseTheActiveDisplayElseThePrimary() {
        let onAirPlay = add(200, frame: onAirPlay)

        let cases: [(name: String, focused: StubWindow?, active: DisplayID?, expected: [DisplayID: Int])] = [
            ("focused window", onAirPlay, Display.standard.id, [Display.standard.id: 1, Display.airPlay.id: 2]),
            ("active display", nil, Display.airPlay.id, [Display.standard.id: 1, Display.airPlay.id: 2]),
            ("active display without an engine", nil, Display.external.id, [Display.standard.id: 2, Display.airPlay.id: 1]),
        ]

        for testCase in cases {
            focused = testCase.focused
            activeDisplay = testCase.active
            let displays = makeDisplays()

            displays.handle(.switchToWorkspace(2))

            XCTAssertEqual(workspaces.mapValues(\.current), testCase.expected, testCase.name)
        }
    }

    func testAnActionReadsTheFocusedWindowAndTheOnScreenListOnce() {
        focused = add(200, frame: onAirPlay)

        displays.handle(.switchToWorkspace(2))

        XCTAssertEqual(focusedReadCount, 1)
        XCTAssertEqual(onScreenReadCount, 1)
    }

    func testAWindowShownOnAnotherDisplayJoinsTheCurrentWorkspaceThereBeforeTheActionRuns() {
        displays.handle(.created(add(100, frame: onStandard).snapshot()))
        let window = add(200, frame: onStandard)
        displays.handle(.created(window.snapshot()))
        window.setPosition(onAirPlay.origin)
        desktops[Display.standard.id]?.clearCalls()

        displays.handle(.switchToWorkspace(2))

        XCTAssertEqual(workspaces[Display.airPlay.id]?.workspace(for: 200), 1)
        XCTAssertEqual(desktops[Display.standard.id]?.reframeCalls.map(\.windowId), [100])
    }

    func testAWindowShownOnAnotherDisplayLeavesItsEngineBeforeARoutedEventOrAResync() {
        let cases: [(name: String, handOn: (Displays, WindowSnapshot) -> Void)] = [
            ("routed event", { $0.handle(.focused($1)) }),
            ("resync", { $0.resync(windows: [$1]) }),
        ]

        for testCase in cases {
            let window = add(200, frame: onStandard)
            let displays = makeDisplays()
            displays.handle(.created(window.snapshot()))
            window.setPosition(onAirPlay.origin)

            testCase.handOn(displays, window.snapshot())

            XCTAssertNil(workspaces[Display.standard.id]?.workspace(for: 200), testCase.name)
        }
    }

    func testARoutedEventReadsTheOnScreenListOnce() {
        displays.handle(.created(add(100, frame: onStandard).snapshot()))

        XCTAssertEqual(onScreenReadCount, 1)
    }

    func testWithOneDisplayAFocusReadsNoOnScreenList() {
        connected = [.standard]
        let window = add(100, frame: onStandard)
        displays.handle(.created(window.snapshot()))
        onScreenReadCount = 0

        displays.handle(.focused(window.snapshot()))

        XCTAssertEqual(onScreenReadCount, 0)
    }

    func testANewWindowGoesToTheDisplayHoldingItsFrame() {
        let cases: [(name: String, event: (WindowSnapshot) -> WindowEvent)] = [
            ("created", WindowEvent.created),
            ("unminimized", WindowEvent.unminimized),
        ]

        for testCase in cases {
            let window = add(200, frame: onAirPlay)
            let displays = makeDisplays()

            displays.handle(testCase.event(window.snapshot()))

            XCTAssertEqual(workspaces[Display.airPlay.id]?.workspace(for: 200), 1, testCase.name)
        }
    }

    func testAFocusedWindowGoesToTheEngineHoldingItElseToTheDisplayHoldingItsFrame() {
        let cases: [(name: String, parkedOnStandard: Bool, expected: Workspaces.Membership)] = [
            ("held", true, .unassigned),
            ("unknown", false, .assigned(1)),
        ]

        for testCase in cases {
            let window = add(200, frame: onStandard)
            let displays = makeDisplays()
            if testCase.parkedOnStandard {
                displays.handle(.created(window.snapshot()))
                displays.handle(.switchToWorkspace(2))
            }
            window.setPosition(onAirPlay.origin)

            displays.handle(.focused(window.snapshot()))

            XCTAssertEqual(workspaces[Display.airPlay.id]?.membership(of: 200), testCase.expected, testCase.name)
        }
    }

    func testAnEventWithoutAFrameGoesToEveryEngine() {
        let window = add(200, frame: onAirPlay)
        displays.handle(.created(window.snapshot()))

        displays.handle(.destroyed(200))

        XCTAssertNil(workspaces[Display.airPlay.id]?.workspace(for: 200))
    }

    func testStartHandsEachEngineTheWindowsOnItsDisplayAndItsSection() {
        let windows = [add(100, frame: onStandard), add(200, frame: onAirPlay)].map { $0.snapshot() }

        displays.start(
            windows: windows,
            restoring: [section(on: .standard, current: 1, 100), section(on: .airPlay, current: 3, 200)]
        )

        XCTAssertEqual(desktops.mapValues(\.recoveredWindowIds), [Display.standard.id: [100], Display.airPlay.id: [200]])
        XCTAssertEqual(workspaces[Display.airPlay.id]?.current, 3)
    }

    func testResyncHandsEachEngineTheWindowsOnItsDisplay() {
        displays.start(windows: [], restoring: nil)

        displays.resync(windows: [add(200, frame: onAirPlay).snapshot()])

        XCTAssertEqual(workspaces[Display.airPlay.id]?.workspace(for: 200), 1)
    }

    func testSavingWritesTheSectionOfEveryDisplay() {
        let cases: [(name: String, save: (Displays) -> Void)] = [
            ("save", { $0.saveState() }),
            ("stop", { $0.stop() }),
        ]

        for testCase in cases {
            let displays = makeDisplays()
            displays.start(windows: [], restoring: nil)

            testCase.save(displays)

            XCTAssertEqual(written.last?.map(\.display), [.standard, .airPlay], testCase.name)
        }
    }

    func testWithNoDisplayReportedOneEngineRuns() {
        connected = []

        displays.handle(.switchToWorkspace(2))

        XCTAssertEqual(workspaces[Display.unknown.id]?.current, 2)
    }

    func testAScreenParametersChangeHandsEachDesktopTheDisplayOfItsId() {
        displays.start(windows: [], restoring: nil)
        connected = [.standard, airPlayOnTheLeft]

        screenParametersChanged?()

        XCTAssertEqual(desktops.mapValues(\.changedDisplays), [Display.standard.id: [.standard], Display.airPlay.id: [airPlayOnTheLeft]])
    }

    func testADisplayAddedGetsAStartedEngine() {
        connected = [.standard]
        displays.start(windows: [], restoring: nil)
        connected = [.standard, .airPlay]

        screenParametersChanged?()
        desktops[Display.airPlay.id]?.report(.screenParametersChange)

        XCTAssertEqual(desktops[Display.airPlay.id]?.reparkedWindowIds, [[]])
    }

    func testARemovedDisplayIsAbsorbedByTheEngineOfThePrimaryDisplay() {
        displays.start(windows: [], restoring: nil)
        displays.handle(.created(add(200, frame: onAirPlay).snapshot()))
        connected = [newPrimary, .standard]

        screenParametersChanged?()

        XCTAssertEqual(workspaces[newPrimary.id]?.workspace(for: 200), 1)
    }

    func testTheStateFileKeepsNoSectionOfARemovedDisplay() {
        let cases: [(name: String, onAirPlay: [CGWindowID])] = [
            ("its engine held no window", []),
            ("its engine held a window", [200]),
        ]

        for testCase in cases {
            let displays = makeDisplays()
            displays.start(windows: [], restoring: nil)
            for windowId in testCase.onAirPlay {
                displays.handle(.created(add(windowId, frame: onAirPlay).snapshot()))
            }
            displays.saveState()
            connected = [.standard]

            screenParametersChanged?()

            XCTAssertEqual(written.last?.map(\.display), [.standard], testCase.name)
            XCTAssertEqual(written.last?.first?.workspaces.workspaces[1]?.windowIds ?? [], testCase.onAirPlay, testCase.name)
            connected = [.standard, .airPlay]
        }
    }

    func testADisplayThatReturnsGetsNoSectionOfItsRemovedEngine() {
        displays.start(windows: [], restoring: nil)
        activeDisplay = Display.airPlay.id
        displays.handle(.switchToWorkspace(3))
        displays.saveState()
        connected = [.standard]
        screenParametersChanged?()
        connected = [.standard, .airPlay]
        screenParametersChanged?()
        let returned = written.count
        activeDisplay = Display.standard.id
        displays.handle(.switchToWorkspace(2))

        displays.saveState()

        let airPlayCurrents = written[returned...].compactMap { $0.first { $0.display == .airPlay }?.workspaces.current }
        XCTAssertEqual(airPlayCurrents, [1])
    }

    func testDisplaysAddedOrRemovedBehindTheLockScreenAreFollowedAtTheUnlock() {
        displays.start(windows: [], restoring: nil)
        displays.handle(.created(add(200, frame: onAirPlay).snapshot()))
        screenIsLocked = true
        connected = [.standard]

        screenParametersChanged?()

        XCTAssertEqual(desktops.mapValues(\.changedDisplays), [Display.standard.id: [.standard], Display.airPlay.id: []])
        XCTAssertNil(workspaces[Display.standard.id]?.workspace(for: 200))

        screenIsLocked = false
        displays.resync(windows: [])

        XCTAssertEqual(workspaces[Display.standard.id]?.workspace(for: 200), 1)
    }

    func testAScreenParametersChangeWithNoDisplayKeepsTheDisplays() {
        displays.start(windows: [], restoring: nil)
        connected = []

        screenParametersChanged?()
        displays.handle(.created(add(200, frame: onAirPlay).snapshot()))

        XCTAssertEqual(desktops.mapValues(\.changedDisplays), [Display.standard.id: [], Display.airPlay.id: []])
        XCTAssertEqual(workspaces[Display.airPlay.id]?.workspace(for: 200), 1)
    }

    func testTheArrangementFollowsAScreenParametersChange() {
        displays.start(windows: [], restoring: nil)
        connected = [.standard, airPlayOnTheLeft]

        screenParametersChanged?()
        displays.handle(.created(add(200, frame: CGRect(x: -1800, y: 100, width: 800, height: 600)).snapshot()))

        XCTAssertEqual(workspaces[Display.airPlay.id]?.workspace(for: 200), 1)
    }
}
