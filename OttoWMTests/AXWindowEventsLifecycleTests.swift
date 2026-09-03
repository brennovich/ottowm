import AppKit
import CoreGraphics
import XCTest

final class AXWindowEventsLifecycleTests: AXWindowEventsTestCase {
    func testStartRegistersTheWindowsTheApplicationLists() {
        let first = harness.addWindow(pid: 901, id: 100)
        let second = harness.addWindow(pid: 901, id: 200)

        let result = start(app)

        XCTAssertEqual(result?.windows.map(\.id), [100, 200])
        XCTAssertEqual(result?.subscription, .active)
        XCTAssertEqual(applications.findWindow(by: 100)?.element, first)
        XCTAssertEqual(applications.findWindow(by: 200)?.element, second)
    }

    func testStartSkipsAWindowWithoutAnId() {
        harness.addWindow(pid: 901, id: 0)

        XCTAssertEqual(start(app)?.windows.count, 0)
    }

    func testStartReportsAnApplicationThatDoesNotAnswerAsUnreachable() {
        harness.unreadyPids = [901]

        XCTAssertEqual(start(app)?.subscription, .unreachable)
    }

    func testStartReportsAnApplicationWithoutNotificationSupportAsUnsupported() {
        harness.unsupportedPids = [901]

        XCTAssertEqual(start(app)?.subscription, .unsupported)
    }

    // Listing the windows of a process that just failed to subscribe costs another
    // round trip that times out the same way, and a window nothing can report on is
    // not worth attaching.
    func testStartDoesNotReadTheWindowsOfAnApplicationThatDidNotSubscribe() {
        harness.unreadyPids = [901]
        harness.addWindow(pid: 901, id: 100)

        XCTAssertEqual(start(app)?.windows.count, 0)
        XCTAssertEqual(harness.listedPids, [])
        XCTAssertNil(applications.findWindow(by: 100))
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

    func testStartRegistersTheFocusedWindowOfTheActiveApplication() {
        harness.addWindow(pid: 901, id: 100)
        let tab = harness.makeElement(id: 300)
        harness.focusedElements[901] = tab

        let result = start(app)

        XCTAssertEqual(result?.windows.map(\.id), [100])
        XCTAssertEqual(result?.focused?.id, 300)
        XCTAssertEqual(applications.findWindow(by: 300)?.element, tab)
    }

    func testStartReportsTheFocusedWindowItAlsoListsOnlyAsFocused() {
        let window = harness.addWindow(pid: 901, id: 100)
        harness.focusedElements[901] = window

        let result = start(app)

        XCTAssertEqual(result?.windows.map(\.id), [])
        XCTAssertEqual(result?.focused?.id, 100)
    }

    func testStartLeavesTheFocusedWindowOfAnInactiveApplicationAlone() {
        harness.focusedElements[901] = harness.makeElement(id: 300)
        app.activated = false

        let result = start(app)

        XCTAssertEqual(result?.windows.map(\.id), [])
        XCTAssertNil(result?.focused)
        XCTAssertNil(applications.findWindow(by: 300))
    }

    func testStartReportsNoEvent() {
        harness.addWindow(pid: 901, id: 100)
        harness.focusedElements[901] = harness.makeElement(id: 300)

        start(app)

        XCTAssertEqual(events, [])
    }

    func testReconcileReportsAndSubscribesTheWindowsOpenedSinceTheLastAttempt() {
        harness.addWindow(pid: 901, id: 100)
        start(app)
        let discovered = harness.addWindow(pid: 901, id: 200)

        let result = windowEvents.reconcile(app)

        XCTAssertEqual(result?.subscription, .active)
        XCTAssertEqual(result?.windows.map(\.id), [200])
        XCTAssertEqual(applications.findWindow(by: 200)?.element, discovered)
        XCTAssertEqual(harness.subscribed[901]?.suffix(3).map(\.notification), windowNotifications)
    }

    func testReconcileOfAnApplicationWithNothingNewAnswersWithNoWindow() {
        harness.addWindow(pid: 901, id: 100)
        start(app)

        let result = windowEvents.reconcile(app)

        XCTAssertEqual(result?.windows.map(\.id), [])
        XCTAssertNil(result?.focused)
    }

    func testReconcileSubscribesTheApplicationAgainWhileItDoesNotAnswer() {
        harness.unreadyPids = [901]
        start(app)
        harness.unreadyPids = []
        let window = harness.addWindow(pid: 901, id: 100)

        let result = windowEvents.reconcile(app)

        XCTAssertEqual(result?.subscription, .active)
        XCTAssertEqual(result?.windows.map(\.id), [100])
        XCTAssertEqual(applications.findWindow(by: 100)?.element, window)
        XCTAssertEqual(harness.appNotificationCount(pid: 901), 2)
    }

    func testReconcileReportsTheApplicationThatStillDoesNotAnswerAsUnreachable() {
        harness.unreadyPids = [901]
        start(app)

        XCTAssertEqual(windowEvents.reconcile(app)?.subscription, .unreachable)
    }

    func testReconcileLeavesTheSubscriptionOfAnApplicationThatAnsweredAlone() {
        harness.addWindow(pid: 901, id: 100)
        start(app)

        windowEvents.reconcile(app)

        XCTAssertEqual(harness.appNotificationCount(pid: 901), 1)
    }

    func testReconcileOfAnUnwatchedApplicationReturnsNil() {
        harness.addWindow(pid: 901, id: 100)

        XCTAssertNil(windowEvents.reconcile(app))
    }

    // A window that is not the active tab of its group is absent from the window list,
    // so listing misses it: attaching the focused window is what registers it.
    func testReconcileAttachesAndReportsTheFocusedWindow() {
        start(app)
        let tab = harness.makeElement(id: 300)
        harness.focusedElements[901] = tab

        XCTAssertEqual(windowEvents.reconcile(app)?.focused?.id, 300)
        XCTAssertEqual(applications.findWindow(by: 300)?.element, tab)
    }

    func testReconcileOfAFocusedWindowWithoutAnIdReportsNothing() {
        start(app)
        harness.focusedElements[901] = harness.makeElement(id: 0)

        let result = windowEvents.reconcile(app)

        XCTAssertEqual(result?.windows.map(\.id), [])
        XCTAssertNil(result?.focused)
    }

    // The focused window of an application that is not the active one is not what has
    // focus, so a reconcile driven by the retry loop must not report it.
    func testReconcileLeavesTheFocusedWindowOfAnInactiveApplicationAlone() {
        start(app)
        harness.focusedElements[901] = harness.makeElement(id: 300)
        app.activated = false

        let result = windowEvents.reconcile(app)

        XCTAssertEqual(result?.windows.map(\.id), [])
        XCTAssertNil(result?.focused)
        XCTAssertNil(applications.findWindow(by: 300))
    }

    func testReconcileReportsNoEvent() {
        start(app)
        harness.addWindow(pid: 901, id: 100)
        harness.focusedElements[901] = harness.makeElement(id: 300)

        _ = windowEvents.reconcile(app)

        XCTAssertEqual(events, [])
    }

    func testDropDeadForgetsAndReportsTheWindowsThatNoLongerAnswer() {
        let alive = harness.addWindow(pid: 901, id: 100)
        let dead = harness.addWindow(pid: 901, id: 200)
        start(app)
        harness.deadElements = [dead]

        windowEvents.runGC()
        windowEvents.runGC()

        XCTAssertEqual(events.descriptions, ["destroyed(200)"])
        XCTAssertNil(applications.findWindow(by: 200))
        XCTAssertEqual(applications.findWindow(by: 100)?.element, alive)
    }

    func testDropDeadKeepsEveryWindowThatStillAnswers() {
        harness.addWindow(pid: 901, id: 100)
        start(app)

        windowEvents.runGC()

        XCTAssertEqual(events, [])
    }

    func testDropDeadReportsNothingWhileTheScreenIsLocked() {
        let window = harness.addWindow(pid: 901, id: 100)
        start(app)
        harness.deadElements = [window]
        harness.screenIsLocked = true

        windowEvents.runGC()
        windowEvents.runGC()

        XCTAssertEqual(events, [])
        XCTAssertNotNil(applications.findWindow(by: 100))
    }

    // A window reads as invalid while its application is still coming back from sleep,
    // and the sweep runs the moment the screen unlocks. One silent pass is a bad moment,
    // not a dead window.
    func testDropDeadKeepsAWindowThatFailsASinglePass() {
        let window = harness.addWindow(pid: 901, id: 100)
        start(app)
        harness.deadElements = [window]

        windowEvents.runGC()

        XCTAssertEqual(events, [])
        XCTAssertNotNil(applications.findWindow(by: 100))
    }

    func testDropDeadClearsTheSuspicionOnAWindowThatAnswersAgain() {
        let window = harness.addWindow(pid: 901, id: 100)
        start(app)
        harness.deadElements = [window]
        windowEvents.runGC()
        harness.deadElements = []
        windowEvents.runGC()

        harness.deadElements = [window]
        windowEvents.runGC()

        XCTAssertEqual(events, [])
        XCTAssertNotNil(applications.findWindow(by: 100))
    }

    // Resync answers with every window the application holds, the ones already attached
    // included: a window attached while the screen was locked reached no workspace, and
    // reporting only what is new would leave it out.
    func testResyncReportsEveryWindowOfAKnownApplication() {
        harness.addWindow(pid: 901, id: 100)
        start(app)
        harness.addWindow(pid: 901, id: 200)
        harness.focusedElements[901] = harness.makeElement(id: 300)

        let result = windowEvents.resync(app)

        XCTAssertEqual(Set(result?.windows.map(\.id) ?? []), [100, 200, 300])
        XCTAssertNil(result?.focused)
        XCTAssertEqual(result?.subscription, .active)
        XCTAssertEqual(events, [])
    }

    func testResyncReportsTheKnownApplicationThatStillDoesNotAnswerAsUnreachable() {
        harness.unreadyPids = [901]
        start(app)

        XCTAssertEqual(windowEvents.resync(app)?.subscription, .unreachable)
    }

    func testResyncSubscribesAnApplicationThatIsNotKnownYet() {
        harness.addWindow(pid: 901, id: 100)

        let result = windowEvents.resync(app)

        XCTAssertEqual(result?.windows.map(\.id), [100])
        XCTAssertNotNil(harness.callbacks[901])
    }

    func testResyncReportsHowAnApplicationThatIsNotKnownYetAnswered() {
        harness.unreadyPids = [901]
        harness.addWindow(pid: 901, id: 100)

        let result = windowEvents.resync(app)

        XCTAssertEqual(result?.subscription, .unreachable)
        XCTAssertEqual(result?.windows.map(\.id), [])
    }
}
