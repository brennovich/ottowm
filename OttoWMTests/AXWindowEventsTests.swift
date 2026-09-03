import ApplicationServices
import CoreGraphics
import XCTest

/// The AX notifications a watched application delivers, translated into `WindowEvent`.
final class AXWindowEventsTests: AXWindowEventsTestCase {
    func testNotificationMapping() {
        let cases: [(notification: String, known: Bool, expected: [String])] = [
            (kAXWindowCreatedNotification, false, ["created(42)"]),
            (kAXFocusedWindowChangedNotification, false, ["focused(42)"]),
            (kAXWindowMiniaturizedNotification, true, ["minimized(42)"]),
            (kAXWindowDeminiaturizedNotification, true, ["unminimized(42)"]),
            ("AXSomethingElse", false, []),
        ]

        for testCase in cases {
            let reported = descriptions(of: testCase.notification) {
                testCase.known ? $0.addWindow(pid: 901, id: 42) : $0.makeElement(id: 42)
            }

            XCTAssertEqual(reported, testCase.expected, testCase.notification)
        }
    }

    func testDestroyedNotificationForgetsAndReportsTheWindow() {
        let element = harness.addWindow(pid: 901, id: 100)
        start()

        notify(element, kAXUIElementDestroyedNotification)

        XCTAssertEqual(events.descriptions, ["destroyed(100)"])
        XCTAssertNil(applications.findWindow(by: 100))
    }

    func testDestroyedNotificationForAnUnknownElementIsDropped() {
        start()

        notify(harness.makeElement(id: 42), kAXUIElementDestroyedNotification)

        XCTAssertEqual(events, [])
    }

    func testFocusedNotificationForAKnownWindowIsReportedAgain() {
        let element = harness.addWindow(pid: 901, id: 100)
        start()

        notify(element, kAXFocusedWindowChangedNotification)
        notify(element, kAXFocusedWindowChangedNotification)

        XCTAssertEqual(events.descriptions, ["focused(100)", "focused(100)"])
    }

    func testRepeatedWindowCreatedNotificationIsDropped() {
        start()
        let element = harness.makeElement(id: 42)

        notify(element, kAXWindowCreatedNotification)
        notify(element, kAXWindowCreatedNotification)

        XCTAssertEqual(events.descriptions, ["created(42)"])
    }

    func testNotificationsForAWindowWithoutAnIdAreDropped() {
        for notification in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification] {
            XCTAssertEqual(descriptions(of: notification) { $0.makeElement(id: 0) }, [], notification)
        }
    }

    func testMiniaturizeNotificationsForAnUnknownWindowAreDropped() {
        for notification in [kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification] {
            XCTAssertEqual(descriptions(of: notification) { $0.makeElement(id: 42) }, [], notification)
        }
    }

    func testNotificationsOnAnAttachedWindowDoNotBuildAWindow() {
        let element = harness.addWindow(pid: 901, id: 100)
        start()

        notify(element, kAXWindowMiniaturizedNotification)
        notify(element, kAXWindowDeminiaturizedNotification)
        notify(element, kAXUIElementDestroyedNotification)

        XCTAssertEqual(events.descriptions, ["minimized(100)", "unminimized(100)", "destroyed(100)"])
        XCTAssertEqual(harness.builtElements, [])
    }

    func testNotificationsOfAnApplicationNoLongerWatchedAreDropped() {
        let element = harness.addWindow(pid: 901, id: 100)
        start()
        windowEvents.stop(app)

        notify(element, kAXUIElementDestroyedNotification)

        XCTAssertEqual(events, [])
    }

    /// Sends one notification against a fixture of its own, so a table row never sees the
    /// windows another row registered.
    private func descriptions(
        of notification: String,
        sentTo element: (AXWindowEventsHarness) -> AXUIElement
    ) -> [String] {
        let harness = AXWindowEventsHarness()
        let windowEvents = harness.windowEvents
        var events: [WindowEvent] = []
        windowEvents.onEvent = { events.append($0) }
        let target = element(harness)
        _ = windowEvents.start(app)

        harness.callbacks[901]?(target, notification)
        return events.descriptions
    }
}
