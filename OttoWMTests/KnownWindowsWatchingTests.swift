import AppKit
import ApplicationServices
import CoreGraphics
import XCTest

final class KnownWindowsWatchingTests: XCTestCase {
    private let harness = KnownWindowsHarness()
    private let app = StubRunningApplication(pid: 901)
    private lazy var known = harness.knownWindows

    @discardableResult
    private func observe(_ app: NSRunningApplication) -> (windows: [WindowSnapshot], subscribed: Bool)? {
        known.observe(app, notify: { _, _ in })
    }

    func testObserveRegistersTheWindowsTheApplicationLists() {
        let first = harness.addWindow(pid: 901, id: 100)
        let second = harness.addWindow(pid: 901, id: 200)

        let result = observe(app)

        XCTAssertEqual(result?.windows.map(\.id), [100, 200])
        XCTAssertEqual(result?.subscribed, true)
        XCTAssertEqual(known.window(for: 100)?.element, first)
        XCTAssertEqual(known.window(for: 200)?.element, second)
    }

    func testObserveSubscribesToTheApplicationAndWindowNotifications() {
        let window = harness.addWindow(pid: 901, id: 100)

        observe(app)

        XCTAssertEqual(harness.notifications(pid: 901), applicationNotifications + windowNotifications)
        XCTAssertEqual(harness.watched[901]?.first?.element, AXUIElementCreateApplication(901))
        XCTAssertEqual(harness.watched[901]?.last?.element, window)
    }

    func testObserveSkipsAWindowWithoutAnId() {
        harness.addWindow(pid: 901, id: 0)

        XCTAssertEqual(observe(app)?.windows.count, 0)
    }

    func testObserveReportsAnApplicationThatDoesNotAnswerAsUnsubscribed() {
        harness.unreadyPids = [901]

        XCTAssertEqual(observe(app)?.subscribed, false)
    }

    func testObserveOfAnAlreadyObservedApplicationReturnsNil() {
        harness.addWindow(pid: 901, id: 100)
        observe(app)

        XCTAssertNil(observe(app))
    }

    func testObserveReturnsNilWhenTheObserverCannotBeCreated() {
        harness.failingObserverPids = [901]
        harness.addWindow(pid: 901, id: 100)

        XCTAssertNil(observe(app))
        XCTAssertNil(known.window(for: 100))
    }

    func testResubscribeReportsTheWindowsFoundSinceTheLastAttempt() {
        harness.unreadyPids = [901]
        observe(app)
        harness.unreadyPids = []
        let window = harness.addWindow(pid: 901, id: 100)

        let result = known.resubscribe(to: app)

        XCTAssertEqual(result?.windows.map(\.id), [100])
        XCTAssertEqual(result?.subscribed, true)
        XCTAssertEqual(known.window(for: 100)?.element, window)
        XCTAssertEqual(harness.appNotificationCount(pid: 901), 2)
    }

    func testResubscribeDoesNotReportTheWindowsAlreadyKnown() {
        harness.unreadyPids = [901]
        harness.addWindow(pid: 901, id: 100)
        observe(app)
        harness.unreadyPids = []

        XCTAssertEqual(known.resubscribe(to: app)?.windows, [])
    }

    func testResubscribeToAnUnobservedApplicationReturnsNil() {
        XCTAssertNil(known.resubscribe(to: app))
    }

    func testRescanRegistersOnlyTheWindowsNotKnownYet() {
        harness.addWindow(pid: 901, id: 100)
        observe(app)
        let discovered = harness.addWindow(pid: 901, id: 200)

        XCTAssertEqual(known.rescan(app).map(\.id), [200])
        XCTAssertEqual(known.window(for: 200)?.element, discovered)
        XCTAssertEqual(harness.watched[901]?.suffix(3).map(\.notification), windowNotifications)
    }

    func testRescanOfAnUnobservedApplicationFindsNothing() {
        harness.addWindow(pid: 901, id: 100)

        XCTAssertEqual(known.rescan(app), [])
    }

    func testWatchRegistersAndSubscribesTheWindow() {
        observe(app)
        let element = harness.makeElement(id: 42)

        XCTAssertEqual(known.watch(element, of: app)?.id, 42)
        XCTAssertEqual(known.window(for: 42)?.element, element)
        XCTAssertEqual(harness.watched[901]?.suffix(3).map(\.notification), windowNotifications)
    }

    func testWatchReturnsNilForAKnownWindowWithoutSubscribingItAgain() {
        let element = harness.addWindow(pid: 901, id: 100)
        observe(app)
        let watchCount = harness.watched[901]?.count

        XCTAssertNil(known.watch(element, of: app))
        XCTAssertEqual(harness.watched[901]?.count, watchCount)
    }

    func testWatchReturnsNilForAWindowWithoutAnId() {
        observe(app)

        XCTAssertNil(known.watch(harness.makeElement(id: 0), of: app))
    }

    func testWatchReturnsNilForAnUnobservedApplication() {
        let element = harness.makeElement(id: 42)

        XCTAssertNil(known.watch(element, of: app))
        XCTAssertNil(known.window(for: 42))
    }

    func testAdoptRegistersAndSubscribesAnUnknownWindow() {
        observe(app)
        let element = harness.makeElement(id: 42)

        XCTAssertEqual(known.adopt(element, of: app)?.id, 42)
        XCTAssertEqual(known.window(for: 42)?.element, element)
        XCTAssertEqual(harness.watched[901]?.suffix(3).map(\.notification), windowNotifications)
    }

    func testAdoptReturnsAKnownWindowWithoutSubscribingItAgain() {
        let element = harness.addWindow(pid: 901, id: 100)
        observe(app)
        let watchCount = harness.watched[901]?.count

        XCTAssertEqual(known.adopt(element, of: app)?.id, 100)
        XCTAssertEqual(harness.watched[901]?.count, watchCount)
    }

    func testAdoptReturnsNilForAWindowWithoutAnId() {
        observe(app)

        XCTAssertNil(known.adopt(harness.makeElement(id: 0), of: app))
    }

    func testAdoptFocusedRegistersAndReturnsTheFocusedWindow() {
        observe(app)
        let element = harness.makeElement(id: 42)
        harness.systemFocusedWindow = AXWindow(element: element, application: app, id: 42)

        let window = known.adoptFocused()

        XCTAssertTrue(window === harness.systemFocusedWindow)
        XCTAssertEqual(known.window(for: 42)?.element, element)
        XCTAssertEqual(harness.watched[901]?.suffix(3).map(\.notification), windowNotifications)
    }

    func testAdoptFocusedWithoutFocusReturnsNil() {
        observe(app)

        XCTAssertNil(known.adoptFocused())
    }

    func testAdoptFocusedKnownWindowReturnsItWithoutSubscribingItAgain() {
        let element = harness.addWindow(pid: 901, id: 100)
        observe(app)
        let watchCount = harness.watched[901]?.count
        harness.systemFocusedWindow = AXWindow(element: element, application: app, id: 100)

        let window = known.adoptFocused()

        XCTAssertTrue(window === harness.systemFocusedWindow)
        XCTAssertEqual(harness.watched[901]?.count, watchCount)
    }

    func testAdoptFocusedOfApplicationRegistersAndSubscribesItsFocusedWindow() {
        observe(app)
        let element = harness.makeElement(id: 42)
        harness.focusedElements[901] = element

        let window = known.adoptFocused(of: app)

        XCTAssertEqual(window?.id, 42)
        XCTAssertEqual(known.window(for: 42)?.element, element)
        XCTAssertEqual(harness.watched[901]?.suffix(3).map(\.notification), windowNotifications)
    }

    func testAdoptFocusedOfApplicationWithoutFocusReturnsNil() {
        observe(app)

        XCTAssertNil(known.adoptFocused(of: app))
    }

    func testAdoptFocusedOfApplicationKnownWindowReturnsItWithoutSubscribingItAgain() {
        let element = harness.addWindow(pid: 901, id: 100)
        observe(app)
        let watchCount = harness.watched[901]?.count
        harness.focusedElements[901] = element

        XCTAssertEqual(known.adoptFocused(of: app)?.id, 100)
        XCTAssertEqual(harness.watched[901]?.count, watchCount)
    }

    func testDropDeadForgetsAndReportsTheWindowsThatNoLongerAnswer() {
        let alive = harness.addWindow(pid: 901, id: 100)
        let dead = harness.addWindow(pid: 901, id: 200)
        observe(app)
        harness.deadElements = [dead]

        XCTAssertEqual(known.dropDead(), [200])
        XCTAssertNil(known.window(for: 200))
        XCTAssertEqual(known.window(for: 100)?.element, alive)
    }

    func testDropDeadKeepsEveryWindowThatStillAnswers() {
        harness.addWindow(pid: 901, id: 100)
        observe(app)

        XCTAssertEqual(known.dropDead(), [])
    }

    func testDropDeadReportsNothingWhileTheScreenIsLocked() {
        let window = harness.addWindow(pid: 901, id: 100)
        observe(app)
        harness.deadElements = [window]
        harness.screenIsLocked = true

        XCTAssertEqual(known.dropDead(), [])
        XCTAssertNotNil(known.window(for: 100))
    }

    func testStopObservingInvalidatesTheObserverAndForgetsTheWindows() {
        let window = harness.addWindow(pid: 901, id: 100)
        observe(app)

        known.stopObserving(app)

        XCTAssertEqual(harness.invalidatedPids, [901])
        XCTAssertNil(known.window(for: 100))
    }

    func testStopObservingAnUnobservedApplicationDoesNothing() {
        known.stopObserving(app)

        XCTAssertEqual(harness.invalidatedPids, [])
    }

    func testStopObservingLetsTheApplicationBeObservedAgain() {
        harness.addWindow(pid: 901, id: 100)
        observe(app)
        known.stopObserving(app)

        XCTAssertEqual(observe(app)?.windows.map(\.id), [100])
    }

    func testIsObserving() {
        XCTAssertFalse(known.isObserving(app))

        observe(app)

        XCTAssertTrue(known.isObserving(app))
    }

    func testWindowOfElementReturnsNilWithoutAnId() {
        let element = harness.makeElement(id: 0)

        XCTAssertNil(known.window(of: element, in: app))
        XCTAssertEqual(known.window(of: harness.makeElement(id: 42), in: app)?.id, 42)
    }
}
