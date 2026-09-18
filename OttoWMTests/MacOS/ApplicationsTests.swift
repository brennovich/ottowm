import ApplicationServices
import CoreGraphics
import XCTest

/// The applications known and the CGWindowID index of their windows, exercised through
/// the `AXWindowEvents` calls that fill it.
final class ApplicationsTests: AXWindowEventsTestCase {
    func testRemoveInvalidatesAndForgetsOnlyThatApplicationsWindows() {
        let other = StubRunningApplication(pid: 902)
        harness.addWindow(pid: 901, id: 100)
        harness.addWindow(pid: 902, id: 200)
        start(app)
        start(other)

        applications.remove(by: app.processIdentifier)

        XCTAssertEqual(harness.invalidatedPids, [901])
        XCTAssertNil(applications.findWindow(by: 100))
        XCTAssertEqual(applications.findWindow(by: 200)?.id, 200)
    }

    func testRemoveOfAnUnwatchedApplicationDoesNothing() {
        applications.remove(by: app.processIdentifier)

        XCTAssertEqual(harness.invalidatedPids, [])
    }

    func testAddRegistersTheApplicationWithoutSubscribingIt() {
        var notifications: [String] = []
        let application = Application(app, channel: AXNotifications(
            subscribe: { notifications.append($1); return .success },
            invalidate: {}
        ))

        applications.add(application)

        XCTAssertNotNil(applications.find(by: 901))
        XCTAssertEqual(notifications, [])
    }
}
