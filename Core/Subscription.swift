import ApplicationServices

final class Subscription {
    /// What a process answered when its notifications were registered.
    enum Outcome: String {
        case active
        /// The process reports it has no such notification. It will not grow one.
        case unsupported
        /// The process did not answer. It may answer a later attempt.
        case unreachable
    }

    private static let applicationNotifications = [
        kAXWindowCreatedNotification,
        kAXFocusedWindowChangedNotification,
    ]

    private static let windowNotifications = [
        kAXUIElementDestroyedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
    ]

    private let element: AXUIElement
    private let channel: AXNotifications
    private let notifications: [String]

    private var isActive = false

    private init(_ element: AXUIElement, channel: AXNotifications, notifications: [String]) {
        self.element = element
        self.channel = channel
        self.notifications = notifications
    }

    static func application(pid: pid_t, channel: AXNotifications) -> Subscription {
        Subscription(
            AXUIElementCreateApplication(pid), channel: channel, notifications: applicationNotifications
        )
    }

    static func window(_ window: AXWindow, channel: AXNotifications) -> Subscription {
        Subscription(window.element, channel: channel, notifications: windowNotifications)
    }

    @discardableResult
    func activate() -> Outcome {
        guard !isActive else { return .active }

        let failures = notifications
            .map { channel.subscribe(element, $0) }
            .filter { $0 != .success }

        isActive = failures.isEmpty
        if isActive { return .active }
        return failures.contains(.notificationUnsupported) ? .unsupported : .unreachable
    }
}
