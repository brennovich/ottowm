import CoreGraphics
import XCTest

final class DisplaysTests: DisplaysTestCase {
    func testAnEngineSeesOnlyTheWindowsOnItsDisplay() {
        displays.handle(.created(add(100, frame: onStandard).snapshot()))
        focused = add(200, frame: onRight)

        displays.handle(.destroyed(100))

        XCTAssertEqual(workspaces[Display.standard.id]?.membership(of: 200), .unassigned)
    }

    func testAnActionGoesToTheDisplayOfTheFocusedWindowElseTheActiveDisplayElseThePrimary() {
        let onRight = add(200, frame: onRight)

        let cases: [(name: String, focused: StubWindow?, active: DisplayID?, expected: [DisplayID: Int])] = [
            ("focused window", onRight, Display.standard.id, [Display.standard.id: 1, Display.right.id: 2]),
            ("active display", nil, Display.right.id, [Display.standard.id: 1, Display.right.id: 2]),
            ("active display without an engine", nil, Display.external.id, [Display.standard.id: 2, Display.right.id: 1]),
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
        focused = add(200, frame: onRight)

        displays.handle(.switchToWorkspace(2))

        XCTAssertEqual(focusedReadCount, 1)
        XCTAssertEqual(onScreenReadCount, 1)
    }

    func testAWindowShownOnAnotherDisplayMovesToTheEngineThereBeforeAnActionAnEventOrAResyncRuns() {
        let cases: [(name: String, run: (Displays, WindowSnapshot) -> Void)] = [
            ("action", { displays, _ in displays.handle(.switchToWorkspace(2)) }),
            ("routed event", { $0.handle(.focused($1)) }),
            ("resync", { $0.resync(windows: [$1]) }),
        ]

        for testCase in cases {
            let displays = makeDisplays()
            displays.handle(.created(add(100, frame: onStandard).snapshot()))
            let window = add(200, frame: onStandard)
            displays.handle(.created(window.snapshot()))
            window.setPosition(onRight.origin)
            desktops[Display.standard.id]?.clearCalls()

            testCase.run(displays, window.snapshot())

            XCTAssertEqual(workspaces[Display.right.id]?.workspace(for: 200), 1, testCase.name)
            XCTAssertNil(workspaces[Display.standard.id]?.workspace(for: 200), testCase.name)
            XCTAssertEqual(desktops[Display.standard.id]?.reframeCalls.filter { $0.windowId == 200 }, [], testCase.name)
        }
    }

    func testAWindowShownOnAnotherDisplayStaysWithItsEngineWhenTheEngineThereRefusesIt() {
        displays.handle(.created(add(300, frame: onRight).snapshot()))
        offScreenWindowIds = [300]
        let window = add(200, frame: onStandard)
        displays.handle(.created(window.snapshot()))
        window.setPosition(onRight.origin)

        displays.resync(windows: [])

        XCTAssertEqual(workspaces[Display.standard.id]?.workspace(for: 200), 1)
    }

    func testWindowEventsAreIgnoredOnlyWhileTheScreenIsLocked() {
        let window = add(200, frame: onStandard)
        displays.handle(.created(window.snapshot()))
        window.setPosition(onRight.origin)
        screenIsLocked = true

        displays.handle(.created(add(300, frame: onStandard).snapshot()))
        displays.handle(.destroyed(200))

        XCTAssertEqual(workspaces[Display.standard.id]?.allWindowIds, [200])

        screenIsLocked = false
        displays.handle(.destroyed(200))

        XCTAssertEqual(workspaces[Display.standard.id]?.allWindowIds, [])
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

    func testAnEventGoesToTheEngineHoldingTheWindowElseToTheDisplayHoldingItsFrame() {
        let cases: [(
            name: String,
            arrange: (Displays, StubWindow) -> Void,
            event: (StubWindow) -> WindowEvent,
            expected: Workspaces.Membership
        )] = [
            ("focused, parked on the standard display, frame on the right", { displays, window in
                displays.handle(.created(window.snapshot()))
                displays.handle(.switchToWorkspace(2))
                window.setPosition(self.onRight.origin)
            }, { .focused($0.snapshot()) }, .unassigned),
            ("created, held by no engine, frame on the right", { _, window in
                window.setPosition(self.onRight.origin)
            }, { .created($0.snapshot()) }, .assigned(1)),
            ("destroyed, held by the right display", { displays, window in
                window.setPosition(self.onRight.origin)
                displays.handle(.created(window.snapshot()))
            }, { .destroyed($0.id) }, .unassigned),
        ]

        for testCase in cases {
            let window = add(200, frame: onStandard)
            let displays = makeDisplays()
            testCase.arrange(displays, window)

            displays.handle(testCase.event(window))

            XCTAssertEqual(workspaces[Display.right.id]?.membership(of: 200), testCase.expected, testCase.name)
        }
    }

    func testStartHandsEachEngineTheWindowsOnItsDisplayAndItsSection() {
        let standard = add(100, frame: onStandard)
        let right = add(200, frame: onRight)

        displays.start(
            windows: [standard, right].map { $0.snapshot() },
            restoring: SavedSession(
                displays: [savedState([(standard, 1)]), savedState(current: 3, [(right, 3)], on: .right)],
                layouts: [Display.external.id: [300: onRight]]
            )
        )

        XCTAssertEqual(desktops.mapValues(\.recoveredWindowIds), [Display.standard.id: [100], Display.right.id: [200]])
        XCTAssertEqual(workspaces[Display.right.id]?.current, 3)
        XCTAssertEqual(layouts.frame(of: 300, on: Display.external.id), onRight)
    }

    func testResyncHandsEachEngineTheWindowsItHoldsElseTheWindowsOnItsDisplay() {
        let parked = add(200, frame: onStandard)
        displays.handle(.created(parked.snapshot()))
        displays.handle(.switchToWorkspace(2))
        parked.setPosition(onRight.origin)

        displays.resync(windows: [parked.snapshot(), add(300, frame: onRight).snapshot()])

        XCTAssertEqual(workspaces[Display.right.id]?.workspace(for: 300), 1)
        XCTAssertEqual(workspaces[Display.right.id]?.membership(of: 200), .unassigned)
    }

    func testSavingWritesTheSectionOfEveryDisplay() {
        let cases: [(name: String, save: (Displays) -> Void)] = [
            ("save", { $0.saveState() }),
            ("stop", { $0.stop() }),
        ]

        for testCase in cases {
            let displays = makeDisplays()
            displays.start(windows: [], restoring: nil)
            layouts.record(onRight, of: 300, on: Display.external.id)

            testCase.save(displays)

            XCTAssertEqual(written.last?.displays.map(\.display), [.standard, .right], testCase.name)
            XCTAssertEqual(written.last?.layouts, [Display.external.id: [300: onRight]], testCase.name)
        }
    }

    func testASaveWritesTheFileOnceAndOnlyWhenTheStateChanged() {
        displays.start(windows: [], restoring: nil)

        displays.saveState()
        XCTAssertEqual(written.count, 1)

        displays.saveState()
        XCTAssertEqual(written.count, 1)

        activeDisplay = Display.right.id
        displays.handle(.switchToWorkspace(2))
        displays.saveState()
        XCTAssertEqual(written.count, 2)
    }

    func testWithNoDisplayReportedOneEngineRuns() {
        connected = []

        displays.handle(.switchToWorkspace(2))

        XCTAssertEqual(workspaces[Display.unknown.id]?.current, 2)
    }
}
