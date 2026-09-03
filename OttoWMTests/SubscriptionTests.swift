import ApplicationServices
import XCTest

final class SubscriptionTests: XCTestCase {
    private var registered: [(element: AXUIElement, notification: String)] = []
    private var answer = AXError.success

    private lazy var channel = AXNotifications(
        subscribe: { element, notification in
            self.registered.append((element, notification))
            return self.answer
        },
        invalidate: {}
    )

    func testApplicationRegistersTheApplicationNotificationsOnTheApplicationElement() {
        let subscription = Subscription.application(pid: 901, channel: channel)

        XCTAssertEqual(subscription.activate(), .active)
        XCTAssertEqual(registered.map(\.notification), applicationNotifications)
        XCTAssertEqual(Set(registered.map(\.element)), [AXUIElementCreateApplication(901)])
    }

    func testWindowRegistersTheWindowNotificationsOnTheWindowElement() {
        let element = AXUIElementCreateApplication(5000)
        let window = AXWindow(element: element, application: StubRunningApplication(pid: 901), id: 42)
        let subscription = Subscription.window(window, channel: channel)

        XCTAssertEqual(subscription.activate(), .active)
        XCTAssertEqual(registered.map(\.notification), windowNotifications)
        XCTAssertEqual(Set(registered.map(\.element)), [element])
    }

    func testActivateReportsAChannelThatDoesNotAnswerAsUnreachable() {
        answer = .cannotComplete
        let subscription = Subscription.application(pid: 901, channel: channel)

        XCTAssertEqual(subscription.activate(), .unreachable)
    }

    func testActivateReportsAProcessWithoutNotificationSupportAsUnsupported() {
        answer = .notificationUnsupported
        let subscription = Subscription.application(pid: 901, channel: channel)

        XCTAssertEqual(subscription.activate(), .unsupported)
    }

    func testActivateDoesNotRegisterAgainAfterAnAttemptThatSucceeded() {
        let subscription = Subscription.application(pid: 901, channel: channel)
        XCTAssertEqual(subscription.activate(), .active)
        let count = registered.count

        XCTAssertEqual(subscription.activate(), .active)
        XCTAssertEqual(registered.count, count)
    }

    func testActivateRegistersAgainAfterAnAttemptThatFailed() {
        answer = .cannotComplete
        let subscription = Subscription.application(pid: 901, channel: channel)
        _ = subscription.activate()
        let count = registered.count
        answer = .success

        XCTAssertEqual(subscription.activate(), .active)
        XCTAssertEqual(registered.count, count * 2)
    }
}
