import AppKit
import ApplicationServices
import CoreGraphics
import XCTest

final class AXWindowTests: XCTestCase {
    private let stub = StubAXAccess()
    private let app = StubRunningApplication(pid: 901)
    private let appElement = AXUIElementCreateApplication(901)
    private lazy var element = stub.makeElement()
    private lazy var window = AXWindow(element: element, application: app, access: stub.access)

    func testSnapshotDecodesTheWindowAttributes() {
        stub.windowIds[element] = 42
        stub.attributes[element] = [
            .subrole: kAXStandardWindowSubrole as NSString,
            .closeButton: stub.makeElement(),
            .minimizeButton: stub.makeElement(),
            .fullScreen: kCFBooleanTrue,
            .minimized: kCFBooleanTrue,
            .position: CGPoint(x: 10, y: 20).axValue,
            .size: CGSize(width: 300, height: 200).axValue,
        ]

        XCTAssertEqual(window.snapshot(), WindowSnapshot(
            id: 42,
            appName: "App",
            isStandard: true,
            hasCloseButton: true,
            hasMinimizeButton: true,
            isFullScreen: true,
            isMinimized: true,
            frame: CGRect(x: 10, y: 20, width: 300, height: 200)
        ))
    }

    func testSnapshotOfAWindowMissingAttributesFallsBackToFalseAndAZeroFrame() {
        stub.windowIds[element] = 42
        stub.attributes[element] = [
            .subrole: kAXDialogSubrole as NSString,
            .position: CGPoint(x: 10, y: 20).axValue,
        ]

        XCTAssertEqual(window.snapshot(), WindowSnapshot(
            id: 42,
            appName: "App",
            isStandard: false,
            hasCloseButton: false,
            hasMinimizeButton: false,
            isFullScreen: false,
            isMinimized: false,
            frame: .zero
        ))
    }

    func testMovableFrameIsReadInOneBatchAndIsNilForAMinimizedWindow() {
        stub.attributes[element] = [
            .minimized: kCFBooleanFalse,
            .position: CGPoint(x: 10, y: 20).axValue,
            .size: CGSize(width: 300, height: 200).axValue,
        ]

        XCTAssertEqual(window.movableFrame(), CGRect(x: 10, y: 20, width: 300, height: 200))
        XCTAssertEqual(stub.reads(of: element).count, 1)

        stub.attributes[element]?[.minimized] = kCFBooleanTrue

        XCTAssertNil(window.movableFrame())
    }

    func testWithoutAnimationsTurnsEnhancedUserInterfaceOffForTheBodyAndBackOn() {
        stub.attributes[appElement] = [.enhancedUserInterface: kCFBooleanTrue]

        let duringBody = window.withoutAnimations { stub.attributes[appElement]?[.enhancedUserInterface] as? Bool }

        XCTAssertEqual(duringBody, false)
        XCTAssertEqual(stub.attributes[appElement]?[.enhancedUserInterface] as? Bool, true)
    }

    func testWithoutAnimationsWritesNothingWhenEnhancedUserInterfaceIsOff() {
        stub.attributes[appElement] = [.enhancedUserInterface: kCFBooleanFalse]

        window.withoutAnimations {}

        XCTAssertTrue(stub.writes.isEmpty)
    }

    func testFrameWritesSetThePositionAndTheSize() {
        window.setPosition(CGPoint(x: 10, y: 20))
        window.setSize(CGSize(width: 300, height: 200))

        XCTAssertEqual(CGPoint(axValue: stub.attributes[element]?[.position]), CGPoint(x: 10, y: 20))
        XCTAssertEqual(CGSize(axValue: stub.attributes[element]?[.size]), CGSize(width: 300, height: 200))
    }

    func testFocusRaisesTheWindowMakesItMainAndActivatesTheApplication() {
        window.focus()

        XCTAssertEqual(stub.actions.map(\.element), [element])
        XCTAssertEqual(stub.actions.map(\.action), [kAXRaiseAction])
        XCTAssertEqual(stub.attributes[element]?[.main] as? Bool, true)
        XCTAssertEqual(stub.activations, [app])
    }

    func testTabCountCountsTheRadioButtonsOfTheFirstTabGroupAndIsAtLeastOne() {
        let cases: [(name: String, children: [[AXUIElement]]?, tabCount: Int)] = [
            ("a window whose children cannot be read", nil, 1),
            ("a tab group without tabs", [[]], 1),
            ("two tab groups after a toolbar", [[radioButton(), radioButton(), group()], [radioButton()]], 2),
        ]

        for testCase in cases {
            let element = stub.makeElement()
            let toolbar = stub.makeElement()
            stub.attributes[element] = testCase.children.map { groups in
                [.children: ([toolbar] + groups.map(tabGroup)) as NSArray]
            }

            let window = AXWindow(element: element, application: app, access: stub.access)

            XCTAssertEqual(window.tabCount(), testCase.tabCount, testCase.name)
        }
    }

    func testIdIsReadOnce() {
        stub.windowIds[element] = 42

        XCTAssertEqual(window.id, 42)
        XCTAssertEqual(window.id, 42)
        XCTAssertEqual(stub.windowIdReads(of: element), 1)
    }

    func testIsAliveIsFalseOnlyForAnInvalidElement() {
        let cases: [(status: AXError, isAlive: Bool)] = [
            (.cannotComplete, true),
            (.invalidUIElement, false),
        ]

        for testCase in cases {
            stub.statuses[element] = testCase.status

            XCTAssertEqual(window.isAlive(), testCase.isAlive, "\(testCase.status.rawValue)")
        }
    }

    func testOwningResolvesASheetToItsWindow() {
        let parent = stub.makeElement()
        let cases: [(name: String, attributes: [AXAttribute: AnyObject], owner: AXUIElement?)] = [
            ("a sheet", [.role: kAXSheetRole as NSString, .window: parent], parent),
            ("a sheet without a window", [.role: kAXSheetRole as NSString], nil),
            ("a window", [.role: kAXWindowRole as NSString, .window: parent], nil),
        ]

        for testCase in cases {
            let element = stub.makeElement()
            stub.attributes[element] = testCase.attributes

            let owner = AXWindow.owning(element, of: app, access: stub.access)

            XCTAssertEqual(owner.element, testCase.owner ?? element, testCase.name)
        }
    }

    func testFocusedOfAnApplicationIsTheOwnerOfItsFocusedElement() {
        let sheet = stub.makeElement()
        stub.attributes[sheet] = [.role: kAXSheetRole as NSString, .window: element]

        XCTAssertNil(AXWindow.focused(of: app, access: stub.access))

        stub.attributes[appElement] = [.focusedWindow: sheet]

        XCTAssertEqual(AXWindow.focused(of: app, access: stub.access)?.element, element)
    }

    private func radioButton() -> AXUIElement {
        child(role: .radioButton)
    }

    private func group() -> AXUIElement {
        child(role: AXRole(rawValue: kAXGroupRole))
    }

    private func tabGroup(_ tabs: [AXUIElement]) -> AXUIElement {
        let element = child(role: .tabGroup)
        stub.attributes[element]?[.children] = tabs as NSArray
        return element
    }

    private func child(role: AXRole) -> AXUIElement {
        let element = stub.makeElement()
        stub.attributes[element] = [.role: role.rawValue as NSString]
        return element
    }
}
