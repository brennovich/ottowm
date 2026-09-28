import XCTest

final class PagerTabViewTests: XCTestCase {
    private let bounds = CGRect(origin: .zero, size: TabShape.size)
    private let view = PagerTabView(number: .stub())

    func testRetractSqueezesTheShapeAgainstTheRightEdgeAndMovesTheBadgeOut() {
        view.retract()

        XCTAssertEqual(view.shapeLayer.frame, CGRect(x: bounds.maxX - 20, y: 0, width: 20, height: bounds.height))
        XCTAssertGreaterThanOrEqual(view.badgeLayer.frame.minX, bounds.maxX)
        XCTAssertTrue(view.isRetracted)
    }

    func testRestoreReturnsTheShapeAndTheBadgeToTheirFullFrames() {
        view.retract()

        view.restore()

        XCTAssertEqual(view.shapeLayer.frame, bounds)
        XCTAssertEqual(view.badgeLayer.frame, PagerTabView.badge)
        XCTAssertFalse(view.isRetracted)
    }

    func testOnlyAnOptionClickOnTheTabIsReported() throws {
        let cases: [(name: String, flags: NSEvent.ModifierFlags, reported: Int)] = [
            ("option click", .option, 1),
            ("plain click", [], 0),
            ("shift click", .shift, 0),
        ]

        for testCase in cases {
            var clicks = 0
            let view = PagerTabView(number: .stub())
            view.optionClicked = { clicks += 1 }
            let window = NSWindow.offscreen(hosting: view)

            view.mouseDown(with: try mouseEvent(.leftMouseDown, flags: testCase.flags, in: window))

            XCTAssertEqual(clicks, testCase.reported, testCase.name)
        }
    }

    func testPressingShrinksTheTabTowardTheScreenCorner() throws {
        let window = NSWindow.offscreen(hosting: view)

        view.mouseDown(with: try mouseEvent(.leftMouseDown, in: window))

        let pressed = view.bodyLayer.frame
        XCTAssertLessThan(pressed.width, bounds.width)
        XCTAssertLessThan(pressed.height, bounds.height)
        XCTAssertEqual(pressed.maxX, bounds.maxX, accuracy: 0.001)
        XCTAssertEqual(pressed.maxY, bounds.maxY, accuracy: 0.001)
    }

    func testReleasingReturnsTheTabToItsFullFrame() throws {
        let window = NSWindow.offscreen(hosting: view)
        view.mouseDown(with: try mouseEvent(.leftMouseDown, in: window))

        view.mouseUp(with: try mouseEvent(.leftMouseUp, in: window))

        XCTAssertEqual(view.bodyLayer.frame, bounds)
    }

    func testTheTabTakesTheFirstClickWhileItsPanelIsNotKey() {
        XCTAssertTrue(view.acceptsFirstMouse(for: nil))
    }

    func testTheTabAcceptsClicksOnItsPanel() {
        XCTAssertTrue(view.acceptsClicks)
    }

    func testTheNumberRollsOnlyWhileTheTabIsRevealed() {
        let cases: [(name: String, prepare: (PagerTabView) -> Void, rolling: [[String]])] = [
            ("revealed", { $0.reveal() }, [[RollingNumber.animationKey], [RollingNumber.animationKey]]),
            ("never revealed", { _ in }, []),
            ("concealed after a reveal", { $0.reveal(); $0.conceal {} }, []),
        ]

        for testCase in cases {
            let number = RollingNumber.stub()
            let view = PagerTabView(number: number)
            withExtendedLifetime(NSWindow.offscreen(hosting: view)) {
                testCase.prepare(view)

                view.show(workspace: 2)
            }

            XCTAssertEqual(number.rolling, testCase.rolling, testCase.name)
            XCTAssertEqual(number.shownValue, "2", testCase.name)
        }
    }

    private func mouseEvent(
        _ type: NSEvent.EventType,
        flags: NSEvent.ModifierFlags = [],
        in window: NSWindow
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: type,
            location: CGPoint(x: 40, y: 20),
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
    }
}
