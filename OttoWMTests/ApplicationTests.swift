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

    func testAttachSubscribesTheWindowNotificationsAndAnswersAttached() {
        let element = AXUIElementCreateApplication(5000)
        let attached = window(id: 42, element: element)

        let attachment = application.attach(attached)

        XCTAssertEqual(attachment, .attached(attached))
        XCTAssertIdentical(attachment.window, attached)
        XCTAssertEqual(watched.map(\.notification), windowNotifications)
        XCTAssertEqual(Set(watched.map(\.element)), [element])
    }

    func testAttachOfAKnownWindowAnswersTheRegisteredInstanceAndDoesNotSubscribeItAgain() {
        let element = AXUIElementCreateApplication(5000)
        let first = window(id: 42, element: element)
        application.attach(first)
        let count = watched.count

        let attachment = application.attach(window(id: 42, element: element))

        XCTAssertEqual(attachment, .known(first))
        XCTAssertIdentical(attachment.window, first)
        XCTAssertEqual(watched.count, count)
    }

    func testAttachFindsAKnownWindowByItsElementWithoutReadingItsId() {
        let element = AXUIElementCreateApplication(5000)
        let first = window(id: 42, element: element)
        application.attach(first)

        XCTAssertEqual(application.attach(AXWindow(element: element, application: app)), .known(first))
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

    func testFindWindowByElementIsTheWindowItWasAttachedWith() {
        let attached = window(id: 42, element: AXUIElementCreateApplication(5000))
        application.attach(attached)

        XCTAssertIdentical(application.findWindow(element: AXUIElementCreateApplication(5000)), attached)
    }

    func testFindWindowByAnUnknownElementReturnsNil() {
        XCTAssertNil(application.findWindow(element: AXUIElementCreateApplication(5000)))
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

        _ = application.detach(element: first.element)

        XCTAssertIdentical(application.findWindow(by: 42), second)
    }

    func testDetachByElementReturnsTheWindowAndForgetsIt() {
        let element = AXUIElementCreateApplication(5000)
        let attached = window(id: 42, element: element)
        application.attach(attached)

        XCTAssertIdentical(application.detach(element: element), attached)
        XCTAssertNil(application.findWindow(element: element))
        XCTAssertNil(application.detach(element: element))
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
