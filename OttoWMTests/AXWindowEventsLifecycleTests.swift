import AppKit
import CoreGraphics
import XCTest

final class AXWindowEventsLifecycleTests: AXWindowEventsTestCase {
    func testStartRegistersTheWindowsTheApplicationListsAndItsFocusedWindow() {
        let first = harness.addWindow(pid: 901, id: 100)
        let second = harness.addWindow(pid: 901, id: 200)
        let tab = harness.makeElement(id: 300)
        harness.focusedElements[901] = tab

        let result = start(app)

        XCTAssertEqual(result?.windows.map(\.id), [100, 200])
        XCTAssertEqual(result?.focused?.id, 300)
        XCTAssertEqual(result?.subscription, .active)
        XCTAssertEqual(applications.findWindow(by: 100)?.element, first)
        XCTAssertEqual(applications.findWindow(by: 200)?.element, second)
        XCTAssertEqual(applications.findWindow(by: 300)?.element, tab)
    }

    func testStartOfAnAlreadyWatchedApplicationReturnsNil() {
        harness.addWindow(pid: 901, id: 100)
        start(app)

        XCTAssertNil(start(app))
    }

    func testStartReturnsNilWhenTheNotificationChannelCannotBeMade() {
        harness.failingNotificationPids = [901]
        harness.addWindow(pid: 901, id: 100)

        XCTAssertNil(start(app))
        XCTAssertNil(applications.findWindow(by: 100))
    }

    func testScansReportNoEvent() {
        harness.addWindow(pid: 901, id: 100)
        start(app)
        harness.addWindow(pid: 901, id: 200)
        harness.focusedElements[901] = harness.makeElement(id: 300)

        _ = windowEvents.discover(app)
        _ = windowEvents.inventory(app)

        XCTAssertEqual(events, [])
    }

    func testDiscoverReportsAndSubscribesTheWindowsOpenedSinceTheLastAttempt() {
        harness.addWindow(pid: 901, id: 100)
        start(app)
        let discovered = harness.addWindow(pid: 901, id: 200)

        let result = windowEvents.discover(app)

        XCTAssertEqual(result?.subscription, .active)
        XCTAssertEqual(result?.windows.map(\.id), [200])
        XCTAssertEqual(applications.findWindow(by: 200)?.element, discovered)
    }

    func testDiscoverOfAnUnwatchedApplicationReturnsNil() {
        harness.addWindow(pid: 901, id: 100)

        XCTAssertNil(windowEvents.discover(app))
    }

    // A window reads as invalid while its application is still coming back from sleep,
    // and the sweep runs the moment the screen unlocks. One silent pass is a bad moment,
    // not a dead window.
    func testSweepDeadWindowsForgetsAndReportsTheWindowsThatFailTwoPasses() {
        let alive = harness.addWindow(pid: 901, id: 100)
        let dead = harness.addWindow(pid: 901, id: 200)
        start(app)
        harness.deadElements = [dead]

        windowEvents.sweepDeadWindows()

        XCTAssertEqual(events, [])
        XCTAssertNotNil(applications.findWindow(by: 200))

        windowEvents.sweepDeadWindows()

        XCTAssertEqual(events.descriptions, ["destroyed(200)"])
        XCTAssertNil(applications.findWindow(by: 200))
        XCTAssertEqual(applications.findWindow(by: 100)?.element, alive)
    }

    func testSweepDeadWindowsReportsNothingWhileTheScreenIsLocked() {
        let window = harness.addWindow(pid: 901, id: 100)
        start(app)
        harness.deadElements = [window]
        harness.screenIsLocked = true

        windowEvents.sweepDeadWindows()
        windowEvents.sweepDeadWindows()

        XCTAssertEqual(events, [])
        XCTAssertNotNil(applications.findWindow(by: 100))
    }

    func testSweepDeadWindowsClearsTheSuspicionOnAWindowThatAnswersAgain() {
        let window = harness.addWindow(pid: 901, id: 100)
        start(app)
        harness.deadElements = [window]
        windowEvents.sweepDeadWindows()
        harness.deadElements = []
        windowEvents.sweepDeadWindows()

        harness.deadElements = [window]
        windowEvents.sweepDeadWindows()

        XCTAssertEqual(events, [])
        XCTAssertNotNil(applications.findWindow(by: 100))
    }

    // An inventory answers with every window the application holds, the ones already
    // attached included: a window attached while the screen was locked reached no workspace, and
    // reporting only what is new would leave it out.
    func testInventoryReportsEveryWindowOfTheApplication() {
        harness.addWindow(pid: 901, id: 100)
        start(app)
        harness.addWindow(pid: 901, id: 200)
        harness.focusedElements[901] = harness.makeElement(id: 300)

        let result = windowEvents.inventory(app)

        XCTAssertEqual(Set(result?.windows.map(\.id) ?? []), [100, 200, 300])
        XCTAssertNil(result?.focused)
        XCTAssertEqual(result?.subscription, .active)
    }

    func testInventoryOfAnUnwatchedApplicationReturnsNil() {
        harness.addWindow(pid: 901, id: 100)

        XCTAssertNil(windowEvents.inventory(app))
        XCTAssertNil(harness.callbacks[901])
    }
}
