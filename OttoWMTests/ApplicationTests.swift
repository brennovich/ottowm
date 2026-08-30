import AppKit
import ApplicationServices
import CoreGraphics
import XCTest

final class ApplicationTests: XCTestCase {
    private let app = StubRunningApplication(pid: 901)
    private var watched: [(element: AXUIElement, notification: String)] = []
    private var invalidated = false
    private var answer = AXError.success

    private lazy var application = Application(app, channel: AXNotifications(
        subscribe: { element, notification in
            self.watched.append((element, notification))
            return self.answer
        },
        invalidate: { self.invalidated = true }
    ))

    private func window(id: CGWindowID, element: AXUIElement = AXUIElementCreateApplication(5000)) -> AXWindow {
        AXWindow(element: element, application: app, id: id)
    }

    func testAttachSubscribesTheWindowNotificationsAndReturnsTheWindow() {
        let element = AXUIElementCreateApplication(5000)

        let attached = application.attach(window(id: 42, element: element))

        XCTAssertEqual(attached?.id, 42)
        XCTAssertEqual(attached?.element, element)
        XCTAssertEqual(watched.map(\.notification), windowNotifications)
        XCTAssertEqual(Set(watched.map(\.element)), [element])
    }

    func testAttachOfAKnownWindowReportsNothingAndDoesNotSubscribeItAgain() {
        let element = AXUIElementCreateApplication(5000)
        _ = application.attach(window(id: 42, element: element))
        let count = watched.count

        XCTAssertNil(application.attach(window(id: 42, element: element)))
        XCTAssertEqual(watched.count, count)
    }

    func testAttachOfAWindowWithoutAnIdReportsNothing() {
        XCTAssertNil(application.attach(window(id: 0)))
        XCTAssertEqual(watched.count, 0)
    }

    func testAttachOfAnApplicationThatDoesNotAnswerStillReturnsTheWindow() {
        answer = .cannotComplete

        XCTAssertEqual(application.attach(window(id: 42))?.id, 42)
    }

    func testFindWindowOfAnAttachedWindowIsTheWindowItWasAttachedWith() {
        let attached = window(id: 42)
        _ = application.attach(attached)

        XCTAssertIdentical(application.findWindow(attached), attached)
    }

    func testFindWindowMatchesAnotherWindowOverTheSameElement() {
        let element = AXUIElementCreateApplication(5000)
        let attached = window(id: 42, element: element)
        _ = application.attach(attached)

        XCTAssertIdentical(application.findWindow(window(id: 42, element: element)), attached)
    }

    func testFindWindowOfAnUnknownWindowReturnsNil() {
        XCTAssertNil(application.findWindow(window(id: 42)))
    }

    func testFindWindowByAnAttachedIdIsTheWindowItWasAttachedWith() {
        let attached = window(id: 42)
        application.attach(attached)

        XCTAssertIdentical(application.findWindow(by: 42), attached)
    }

    func testFindWindowByAnUnknownIdReturnsNil() {
        XCTAssertNil(application.findWindow(by: 42))
    }

    func testDetachKeepsTheIdHeldByAnotherElementOfTheSameTabGroup() {
        let first = window(id: 42, element: AXUIElementCreateApplication(5000))
        let second = window(id: 42, element: AXUIElementCreateApplication(5001))
        application.attach(first)
        application.attach(second)

        _ = application.detach(first)

        XCTAssertIdentical(application.findWindow(by: 42), second)
    }

    func testDetachReturnsTheWindowAndForgetsIt() {
        let attached = window(id: 42)
        _ = application.attach(attached)

        XCTAssertIdentical(application.detach(attached), attached)
        XCTAssertNil(application.findWindow(attached))
        XCTAssertNil(application.detach(attached))
    }

    func testWindowsListsTheAttachedWindows() {
        _ = application.attach(window(id: 42, element: AXUIElementCreateApplication(5000)))
        _ = application.attach(window(id: 43, element: AXUIElementCreateApplication(5001)))

        XCTAssertEqual(application.windows.map(\.id).sorted(), [42, 43])
    }

    func testInvalidateEndsEverySubscriptionMadeThroughTheChannel() {
        application.invalidate()

        XCTAssertTrue(invalidated)
    }
}
