import ApplicationServices
import CoreGraphics
import XCTest

/// The applications known and the CGWindowID index of their windows, exercised through
/// the `AXWindowEvents` calls that fill it.
final class ApplicationsTests: AXWindowEventsTestCase {
    private func destroy(_ element: AXUIElement) {
        notify(element, kAXUIElementDestroyedNotification)
    }

    func testWindowForIdReturnsTheRegisteredWindow() {
        let element = harness.addWindow(pid: 901, id: 100)
        start(app)

        let window = applications.findWindow(by: 100)

        XCTAssertEqual(window?.id, 100)
        XCTAssertEqual(window?.element, element)
        XCTAssertEqual(window?.application.processIdentifier, 901)
    }

    func testWindowForUnknownIdReturnsNil() {
        start(app)

        XCTAssertNil(applications.findWindow(by: 100))
    }

    func testMatchesElementsByValueNotByInstance() {
        let element = AXUIElementCreateApplication(904)
        harness.windowIds[element] = 100
        harness.elements[901] = [element]
        start(app)

        destroy(AXUIElementCreateApplication(904))

        XCTAssertNil(applications.findWindow(by: 100))
    }

    func testRemoveForgetsOnlyThatApplicationsWindows() {
        let other = StubRunningApplication(pid: 902)
        harness.addWindow(pid: 901, id: 100)
        harness.addWindow(pid: 902, id: 200)
        start(app)
        start(other)

        applications.remove(by: app.processIdentifier)

        XCTAssertNil(applications.findWindow(by: 100))
        XCTAssertEqual(applications.findWindow(by: 200)?.id, 200)
    }

    func testRemovedWindowIsFoundAgainByDiscovery() {
        let element = harness.addWindow(pid: 901, id: 100)
        start(app)
        destroy(element)

        XCTAssertEqual(windowEvents.discover(app)?.subscription, .active)
        XCTAssertEqual(applications.findWindow(by: 100)?.element, element)
    }

    func testRemoveInvalidatesTheNotificationsAndForgetsTheWindows() {
        _ = harness.addWindow(pid: 901, id: 100)
        start(app)

        applications.remove(by: app.processIdentifier)

        XCTAssertEqual(harness.invalidatedPids, [901])
        XCTAssertNil(applications.findWindow(by: 100))
    }

    func testRemoveOfAnUnwatchedApplicationDoesNothing() {
        applications.remove(by: app.processIdentifier)

        XCTAssertEqual(harness.invalidatedPids, [])
    }

    func testRemoveLetsTheApplicationBeStartedAgain() {
        harness.addWindow(pid: 901, id: 100)
        start(app)
        applications.remove(by: app.processIdentifier)

        XCTAssertEqual(start(app)?.windows.map(\.id), [100])
    }

    func testAddSubscribesTheApplicationsNotifications() {
        var notifications: [String] = []
        let application = Application(app, channel: AXNotifications(
            subscribe: { notifications.append($1); return .success },
            invalidate: {}
        ))

        XCTAssertEqual(applications.add(application).subscription, .active)
        XCTAssertEqual(notifications, applicationNotifications)
        XCTAssertNotNil(applications.find(by: 901))
    }
}
