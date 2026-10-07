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

    func testAWindowShownOnAnotherDisplayJoinsTheCurrentWorkspaceThereBeforeTheActionRuns() {
        displays.handle(.created(add(100, frame: onStandard).snapshot()))
        let window = add(200, frame: onStandard)
        displays.handle(.created(window.snapshot()))
        window.setPosition(onRight.origin)
        desktops[Display.standard.id]?.clearCalls()

        displays.handle(.switchToWorkspace(2))

        XCTAssertEqual(workspaces[Display.right.id]?.workspace(for: 200), 1)
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
            window.setPosition(onRight.origin)

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
            let window = add(200, frame: onRight)
            let displays = makeDisplays()

            displays.handle(testCase.event(window.snapshot()))

            XCTAssertEqual(workspaces[Display.right.id]?.workspace(for: 200), 1, testCase.name)
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
            window.setPosition(onRight.origin)

            displays.handle(.focused(window.snapshot()))

            XCTAssertEqual(workspaces[Display.right.id]?.membership(of: 200), testCase.expected, testCase.name)
        }
    }

    func testAnEventWithoutAFrameGoesToEveryEngine() {
        let window = add(200, frame: onRight)
        displays.handle(.created(window.snapshot()))

        displays.handle(.destroyed(200))

        XCTAssertNil(workspaces[Display.right.id]?.workspace(for: 200))
    }

    func testStartHandsEachEngineTheWindowsOnItsDisplayAndItsSection() {
        let standard = add(100, frame: onStandard)
        let right = add(200, frame: onRight)

        displays.start(
            windows: [standard, right].map { $0.snapshot() },
            restoring: [savedState([(standard, 1)]), savedState(current: 3, [(right, 3)], on: .right)]
        )

        XCTAssertEqual(desktops.mapValues(\.recoveredWindowIds), [Display.standard.id: [100], Display.right.id: [200]])
        XCTAssertEqual(workspaces[Display.right.id]?.current, 3)
    }

    func testResyncHandsEachEngineTheWindowsOnItsDisplay() {
        displays.start(windows: [], restoring: nil)

        displays.resync(windows: [add(200, frame: onRight).snapshot()])

        XCTAssertEqual(workspaces[Display.right.id]?.workspace(for: 200), 1)
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

            XCTAssertEqual(written.last?.map(\.display), [.standard, .right], testCase.name)
        }
    }

    func testWithNoDisplayReportedOneEngineRuns() {
        connected = []

        displays.handle(.switchToWorkspace(2))

        XCTAssertEqual(workspaces[Display.unknown.id]?.current, 2)
    }
}
