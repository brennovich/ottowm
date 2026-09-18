import AppKit
import ApplicationServices
import CoreGraphics
import XCTest

final class ApplicationTests: XCTestCase {
    private let app = StubRunningApplication(pid: 901)
    private let ax = StubAXAccess()
    private let appElement = AXUIElementCreateApplication(901)
    private var watched: [(element: AXUIElement, notification: String)] = []
    private var invalidated = false
    private var answer = AXError.success

    private lazy var application = Application(
        app,
        channel: AXNotifications(
            subscribe: { element, notification in
                self.watched.append((element, notification))
                return self.answer
            },
            invalidate: { self.invalidated = true }
        ),
        access: ax.access
    )

    private func window(id: CGWindowID, element: AXUIElement = AXUIElementCreateApplication(5000)) -> AXWindow {
        AXWindow(element: element, application: app, id: id, access: ax.access)
    }

    private func list(_ windows: [AXWindow]) {
        for window in windows { ax.windowIds[window.element] = window.id }
        ax.attributes[appElement, default: [:]][.windows] = windows.map(\.element) as NSArray
    }

    private func focus(_ window: AXWindow) {
        ax.windowIds[window.element] = window.id
        ax.attributes[appElement, default: [:]][.focusedWindow] = window.element
    }

    func testScanSubscribesTheApplicationAndAttachesTheListedWindowsItDoesNotHold() {
        let held = window(id: 42, element: AXUIElementCreateApplication(5000))
        let new = window(id: 43, element: AXUIElementCreateApplication(5001))
        application.attach(held)
        list([held, new])

        let scan = application.scan()

        XCTAssertEqual(scan.subscription, .active)
        XCTAssertEqual(scan.windows, [new])
        XCTAssertNil(scan.focused)
        XCTAssertEqual(watched.count, 2 * windowNotifications.count + applicationNotifications.count)
        XCTAssertEqual(application.windows.map(\.id).sorted(), [42, 43])
    }

    func testScanOfAnApplicationThatDoesNotReplyReadsNoWindow() {
        answer = .cannotComplete
        list([window(id: 42)])
        focus(window(id: 300, element: AXUIElementCreateApplication(5002)))

        let scan = application.scan()

        XCTAssertEqual(scan.subscription, .unreachable)
        XCTAssertEqual(scan.windows, [])
        XCTAssertNil(scan.focused)
        XCTAssertEqual(ax.reads(of: appElement), [])
        XCTAssertEqual(application.windows, [])
    }

    func testScanAttachesTheFocusedWindowOfTheActiveApplicationFirstAndReturnsItApart() {
        let tab = window(id: 300, element: AXUIElementCreateApplication(5002))
        let other = window(id: 42, element: AXUIElementCreateApplication(5000))
        focus(tab)
        list([tab, other])

        let scan = application.scan()

        XCTAssertEqual(scan.focused, tab)
        XCTAssertEqual(scan.windows, [other])
        XCTAssertEqual(application.findWindow(by: 300), tab)
    }

    func testScanLeavesTheFocusedWindowOfAnInactiveApplicationUnread() {
        app.activated = false
        focus(window(id: 300, element: AXUIElementCreateApplication(5002)))

        let scan = application.scan()

        XCTAssertNil(scan.focused)
        XCTAssertEqual(ax.reads(of: .focusedWindow, on: appElement), 0)
        XCTAssertEqual(application.windows, [])
    }

    func testAttachSubscribesTheWindowNotificationsAndReturnsAttached() {
        let element = AXUIElementCreateApplication(5000)
        let attached = window(id: 42, element: element)

        let attachment = application.attach(attached)

        XCTAssertEqual(attachment, .attached(attached))
        XCTAssertIdentical(attachment.window, attached)
        XCTAssertEqual(watched.map(\.notification), windowNotifications)
        XCTAssertEqual(Set(watched.map(\.element)), [element])
    }

    func testAttachOfAKnownWindowReturnsTheRegisteredInstanceWithoutReadingItsIdOrSubscribingItAgain() {
        let element = AXUIElementCreateApplication(5000)
        let first = window(id: 42, element: element)
        application.attach(first)
        let count = watched.count

        let attachment = application.attach(AXWindow(element: element, application: app, access: ax.access))

        XCTAssertEqual(attachment, .known(first))
        XCTAssertIdentical(attachment.window, first)
        XCTAssertEqual(ax.windowIdReads(of: element), 0)
        XCTAssertEqual(watched.count, count)
    }

    func testAttachOfAWindowWithoutAnIdReturnsRejected() {
        let attachment = application.attach(window(id: 0))

        XCTAssertEqual(attachment, .rejected)
        XCTAssertNil(attachment.window)
        XCTAssertEqual(watched.count, 0)
    }

    func testAttachOfAnApplicationThatDoesNotReplyStillAttachesTheWindow() {
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
