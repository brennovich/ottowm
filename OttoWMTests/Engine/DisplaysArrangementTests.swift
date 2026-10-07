import CoreGraphics
import XCTest

final class DisplaysArrangementTests: DisplaysTestCase {
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

    func testARemovedDisplayIsReported() {
        displays.start(windows: [], restoring: nil)
        connected = [.standard]

        screenParametersChanged?()

        XCTAssertEqual(removed, [Display.airPlay.id])
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

    func testAScreenChangeBehindTheLockScreenIsFollowedAtTheUnlock() {
        let standardWithNewGeometry = Display(
            id: Display.standard.id,
            fullFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 875)
        )
        displays.start(windows: [], restoring: nil)
        displays.handle(.created(add(200, frame: onAirPlay).snapshot()))
        screenIsLocked = true
        connected = [standardWithNewGeometry]

        screenParametersChanged?()

        XCTAssertEqual(desktops.mapValues(\.changedDisplays), [Display.standard.id: [], Display.airPlay.id: []])
        XCTAssertNil(workspaces[Display.standard.id]?.workspace(for: 200))

        screenIsLocked = false
        displays.resync(windows: [])

        XCTAssertEqual(desktops[Display.standard.id]?.changedDisplays, [standardWithNewGeometry])
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
