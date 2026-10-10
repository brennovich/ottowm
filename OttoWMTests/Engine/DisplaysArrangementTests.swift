import CoreGraphics
import XCTest

final class DisplaysArrangementTests: DisplaysTestCase {
    private let rightMovedLeft = Display(
        id: Display.right.id,
        fullFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: -1920, y: 25, width: 1920, height: 1055)
    )
    private let newPrimary = Display(
        id: DisplayID(rawValue: "new-primary"),
        fullFrame: CGRect(x: -2560, y: 0, width: 2560, height: 1440),
        visibleFrame: CGRect(x: -2560, y: 25, width: 2560, height: 1415)
    )

    func testAScreenParametersChangeHandsEachDesktopTheDisplayOfItsIdFromTheArrangement() {
        displays.start(windows: [], restoring: nil)
        connected = [.standard, rightMovedLeft]

        screenParametersChanged?()

        XCTAssertEqual(
            desktops.mapValues(\.changedDisplays),
            [Display.standard.id: [.standard], Display.right.id: [rightMovedLeft]]
        )
    }

    func testADisplayAddedGetsAStartedEngine() {
        connected = [.standard]
        displays.start(windows: [], restoring: nil)
        connected = [.standard, .right]

        screenParametersChanged?()
        desktops[Display.right.id]?.report(.screenParametersChange)

        XCTAssertEqual(desktops[Display.right.id]?.reparkedWindowIds, [[]])
    }

    func testARemovedDisplayIsAbsorbedByTheEngineOfThePrimaryDisplayAndReported() {
        displays.start(windows: [], restoring: nil)
        displays.handle(.created(add(200, frame: onRight).snapshot()))
        connected = [newPrimary, .standard]

        screenParametersChanged?()

        XCTAssertEqual(workspaces[newPrimary.id]?.workspace(for: 200), 1)
        XCTAssertEqual(removed, [Display.right.id])
    }

    func testTheStateFileKeepsNoSectionOfARemovedDisplay() {
        displays.start(windows: [], restoring: nil)
        displays.handle(.created(add(200, frame: onRight).snapshot()))
        displays.saveState()
        connected = [.standard]

        screenParametersChanged?()

        XCTAssertEqual(written.last?.displays.map(\.display), [.standard])
        XCTAssertEqual(written.last?.displays.first?.workspaces.workspaces[1]?.windowIds, [200])
    }

    func testADisplayThatReturnsGetsNoSectionOfItsRemovedEngine() {
        displays.start(windows: [], restoring: nil)
        activeDisplay = Display.right.id
        displays.handle(.switchToWorkspace(3))
        displays.saveState()
        connected = [.standard]
        screenParametersChanged?()
        connected = [.standard, .right]
        screenParametersChanged?()
        let returned = written.count
        activeDisplay = Display.standard.id
        displays.handle(.switchToWorkspace(2))

        displays.saveState()

        let rightCurrents = written[returned...].compactMap { $0.displays.first { $0.display == .right }?.workspaces.current }
        XCTAssertEqual(rightCurrents, [1])
    }

    func testAScreenChangeBehindTheLockScreenIsFollowedAtTheUnlock() {
        let standardWithNewGeometry = Display(
            id: Display.standard.id,
            fullFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 875)
        )
        displays.start(windows: [], restoring: nil)
        displays.handle(.created(add(200, frame: onRight).snapshot()))
        screenIsLocked = true
        connected = [standardWithNewGeometry]

        screenParametersChanged?()

        XCTAssertEqual(desktops.mapValues(\.changedDisplays), [Display.standard.id: [], Display.right.id: []])
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
        displays.handle(.created(add(200, frame: onRight).snapshot()))

        XCTAssertEqual(desktops.mapValues(\.changedDisplays), [Display.standard.id: [], Display.right.id: []])
        XCTAssertEqual(workspaces[Display.right.id]?.workspace(for: 200), 1)
    }

    func testTheArrangementFollowsAScreenParametersChange() {
        displays.start(windows: [], restoring: nil)
        connected = [.standard, rightMovedLeft]

        screenParametersChanged?()
        displays.handle(.created(add(200, frame: CGRect(x: -1800, y: 100, width: 800, height: 600)).snapshot()))

        XCTAssertEqual(workspaces[Display.right.id]?.workspace(for: 200), 1)
    }
}
