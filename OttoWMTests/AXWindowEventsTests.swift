import ApplicationServices
import CoreGraphics
import XCTest

/// The AX notifications a watched application delivers, translated into `WindowEvent`.
final class AXWindowEventsTests: AXWindowEventsTestCase {
    func testNotificationMapping() {
        let cases: [(notification: String, known: Bool, id: CGWindowID, expected: [String])] = [
            (kAXWindowCreatedNotification, false, 42, ["created(42)"]),
            (kAXWindowCreatedNotification, false, 0, []),
            (kAXFocusedWindowChangedNotification, false, 42, ["focused(42)"]),
            (kAXFocusedWindowChangedNotification, false, 0, []),
            (kAXUIElementDestroyedNotification, true, 42, ["destroyed(42)"]),
            (kAXUIElementDestroyedNotification, false, 42, []),
            (kAXWindowMiniaturizedNotification, true, 42, ["minimized(42)"]),
            (kAXWindowMiniaturizedNotification, false, 42, []),
            (kAXWindowDeminiaturizedNotification, true, 42, ["unminimized(42)"]),
            (kAXWindowDeminiaturizedNotification, false, 42, []),
            ("AXSomethingElse", false, 42, []),
        ]

        for testCase in cases {
            let reported = descriptions(of: testCase.notification) {
                testCase.known ? $0.addWindow(pid: 901, id: testCase.id) : $0.makeElement(id: testCase.id)
            }

            XCTAssertEqual(
                reported, testCase.expected, "\(testCase.notification) known=\(testCase.known) id=\(testCase.id)"
            )
        }
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

    func testAdoptFocusedWindowAttachesTheWindowInFrontOnceAndAnswersIt() {
        start()
        let tab = harness.makeElement(id: 300)
        harness.frontmost = harness.window(tab, of: app)

        XCTAssertEqual(windowEvents.adoptFocusedWindow()?.id, 300)
        XCTAssertEqual(applications.findWindow(by: 300)?.element, tab)
        XCTAssertEqual(events, [])

        let count = harness.subscribed[901]?.count

        XCTAssertEqual(windowEvents.adoptFocusedWindow()?.id, 300)
        XCTAssertEqual(harness.subscribed[901]?.count, count)
    }

    func testAdoptFocusedWindowOfAnUnwatchedApplicationAnswersNil() {
        harness.frontmost = harness.window(harness.makeElement(id: 300), of: app)

        XCTAssertNil(windowEvents.adoptFocusedWindow())
        XCTAssertNil(applications.findWindow(by: 300))
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
