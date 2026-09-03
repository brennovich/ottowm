import AppKit
import ApplicationServices
import CoreGraphics
import XCTest

final class ApplicationTests: XCTestCase {
    private let app = StubRunningApplication(pid: 901)
    private var watched: [(element: AXUIElement, notification: String)] = []
    private var invalidated = false
    private var answer = AXError.success
    private var listed: [AXWindow] = []
    private var focused: AXWindow?
    private var listings = 0
    private var focusedReads = 0

    private lazy var application = Application(
        app,
        channel: AXNotifications(
            subscribe: { element, notification in
                self.watched.append((element, notification))
                return self.answer
            },
            invalidate: { self.invalidated = true }
        ),
        focusedWindow: { _ in
            self.focusedReads += 1
            return self.focused
        },
        listedWindows: { _ in
            self.listings += 1
            return self.listed
        }
    )

    private func window(id: CGWindowID, element: AXUIElement = AXUIElementCreateApplication(5000)) -> AXWindow {
        AXWindow(element: element, application: app, id: id)
    }

    func testScanSubscribesTheApplicationAndAttachesTheListedWindowsItDoesNotHold() {
        let held = window(id: 42, element: AXUIElementCreateApplication(5000))
        let new = window(id: 43, element: AXUIElementCreateApplication(5001))
        application.attach(held)
        listed = [held, new]

        let scan = application.scan()

        XCTAssertEqual(scan.subscription, .active)
        XCTAssertEqual(scan.windows, [new])
        XCTAssertNil(scan.focused)
        XCTAssertEqual(watched.count, 2 * windowNotifications.count + applicationNotifications.count)
        XCTAssertEqual(application.windows.map(\.id).sorted(), [42, 43])
    }

    func testScanOfAnApplicationThatDoesNotAnswerReadsNoWindow() {
        answer = .cannotComplete
        listed = [window(id: 42)]
        focused = window(id: 300, element: AXUIElementCreateApplication(5002))

        let scan = application.scan()

        XCTAssertEqual(scan.subscription, .unreachable)
        XCTAssertEqual(scan.windows, [])
        XCTAssertNil(scan.focused)
        XCTAssertEqual(listings, 0)
        XCTAssertEqual(focusedReads, 0)
        XCTAssertEqual(application.windows, [])
    }

    func testScanAttachesTheFocusedWindowOfTheActiveApplicationFirstAndAnswersItApart() {
        let tab = window(id: 300, element: AXUIElementCreateApplication(5002))
        let other = window(id: 42, element: AXUIElementCreateApplication(5000))
        focused = tab
        listed = [tab, other]

        let scan = application.scan()

        XCTAssertIdentical(scan.focused, tab)
        XCTAssertEqual(scan.windows, [other])
        XCTAssertIdentical(application.findWindow(by: 300), tab)
    }

    func testScanLeavesTheFocusedWindowOfAnInactiveApplicationUnread() {
        app.activated = false
        focused = window(id: 300, element: AXUIElementCreateApplication(5002))

        let scan = application.scan()

        XCTAssertNil(scan.focused)
        XCTAssertEqual(focusedReads, 0)
        XCTAssertEqual(application.windows, [])
    }

    func testAttachSubscribesTheWindowNotificationsAndAnswersAttached() {
        let element = AXUIElementCreateApplication(5000)
        let attached = window(id: 42, element: element)

        let attachment = application.attach(attached)

        XCTAssertEqual(attachment, .attached(attached))
        XCTAssertIdentical(attachment.window, attached)
        XCTAssertEqual(watched.map(\.notification), windowNotifications)
        XCTAssertEqual(Set(watched.map(\.element)), [element])
    }

    func testAttachOfAKnownWindowAnswersTheRegisteredInstanceWithoutReadingItsIdOrSubscribingItAgain() {
        let element = AXUIElementCreateApplication(5000)
        let first = window(id: 42, element: element)
        application.attach(first)
        let count = watched.count

        let attachment = application.attach(AXWindow(element: element, application: app))

        XCTAssertEqual(attachment, .known(first))
        XCTAssertIdentical(attachment.window, first)
        XCTAssertEqual(watched.count, count)
    }

    func testAttachOfAWindowWithoutAnIdAnswersRejected() {
        let attachment = application.attach(window(id: 0))

        XCTAssertEqual(attachment, .rejected)
        XCTAssertNil(attachment.window)
        XCTAssertEqual(watched.count, 0)
    }

    func testAttachOfAnApplicationThatDoesNotAnswerStillAttachesTheWindow() {
        answer = .cannotComplete
        let attached = window(id: 42)

        XCTAssertEqual(application.attach(attached), .attached(attached))
    }

    func testFindWindowByElementIsTheWindowItWasAttachedWithAndNilForAnyOther() {
        let attached = window(id: 42, element: AXUIElementCreateApplication(5000))
        application.attach(attached)

        XCTAssertIdentical(application.findWindow(element: AXUIElementCreateApplication(5000)), attached)
        XCTAssertNil(application.findWindow(element: AXUIElementCreateApplication(5001)))
    }

    func testFindWindowByAnAttachedIdIsTheWindowItWasAttachedWithAndNilForAnyOther() {
        let attached = window(id: 42)
        application.attach(attached)

        XCTAssertIdentical(application.findWindow(by: 42), attached)
        XCTAssertNil(application.findWindow(by: 43))
    }

    func testDetachKeepsTheIdHeldByAnotherElementOfTheSameTabGroup() {
        let first = window(id: 42, element: AXUIElementCreateApplication(5000))
        let second = window(id: 42, element: AXUIElementCreateApplication(5001))
        application.attach(first)
        application.attach(second)

        _ = application.detach(element: first.element)

        XCTAssertIdentical(application.findWindow(by: 42), second)
    }

    func testDetachByElementReturnsTheWindowAndForgetsIt() {
        let element = AXUIElementCreateApplication(5000)
        let attached = window(id: 42, element: element)
        application.attach(attached)

        XCTAssertIdentical(application.detach(element: element), attached)
        XCTAssertNil(application.findWindow(element: element))
        XCTAssertNil(application.findWindow(by: 42))
        XCTAssertNil(application.detach(element: element))
    }

    func testInvalidateEndsEverySubscriptionMadeThroughTheChannel() {
        application.invalidate()

        XCTAssertTrue(invalidated)
    }
}
