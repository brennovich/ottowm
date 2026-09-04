import AppKit
import ApplicationServices
import CoreGraphics

final class Application {
    /// `known` carries the instance registered earlier, whose id is already read.
    enum Attachment: Equatable {
        case attached(AXWindow)
        case known(AXWindow)
        case rejected

        var window: AXWindow? {
            switch self {
            case let .attached(window), let .known(window): window
            case .rejected: nil
            }
        }
    }

    struct Scan {
        let subscription: Subscription.Outcome
        let windows: [AXWindow]
        let focused: AXWindow?
    }

    let running: NSRunningApplication

    private let channel: AXNotifications
    private let subscription: Subscription
    private let focusedWindow: (NSRunningApplication) -> AXWindow?
    private let listedWindows: (NSRunningApplication) -> [AXWindow]
    private var attached: [AXUIElement: AXWindow] = [:]
    private var windowsById: [CGWindowID: AXWindow] = [:]

    var pid: pid_t { running.processIdentifier }
    var name: String { running.localizedName ?? "" }
    var windows: [AXWindow] { Array(attached.values) }

    init(
        _ running: NSRunningApplication,
        channel: AXNotifications,
        focusedWindow: @escaping (NSRunningApplication) -> AXWindow? = AXWindow.focused(of:),
        listedWindows: @escaping (NSRunningApplication) -> [AXWindow] = AXWindow.all(of:)
    ) {
        self.running = running
        self.channel = channel
        self.subscription = .application(pid: running.processIdentifier, channel: channel)
        self.focusedWindow = focusedWindow
        self.listedWindows = listedWindows
    }

    func scan() -> Scan {
        let outcome = subscription.activate()
        guard outcome == .active else { return Scan(subscription: outcome, windows: [], focused: nil) }

        let focused = attachFocusedWindow()
        let windows = listedWindows(running).compactMap { window -> AXWindow? in
            guard case let .attached(attached) = attach(window) else { return nil }
            return attached
        }

        return Scan(subscription: outcome, windows: windows, focused: focused)
    }

    @discardableResult
    func attach(_ window: AXWindow) -> Attachment {
        if let known = findWindow(element: window.element) { return .known(known) }
        guard window.id != 0 else { return .rejected }

        Subscription.window(window, channel: channel).activate()
        attached[window.element] = window
        windowsById[window.id] = window

        Log.windows.info("subscribing \(window.logDescription)")
        return .attached(window)
    }

    func findWindow(element: AXUIElement) -> AXWindow? {
        attached[element]
    }

    func findWindow(by id: CGWindowID) -> AXWindow? {
        windowsById[id]
    }

    func detach(element: AXUIElement) -> AXWindow? {
        guard let removed = attached.removeValue(forKey: element) else { return nil }

        // Tabs of one group share an id, so the entry may point at another window.
        if windowsById[removed.id] == removed {
            windowsById[removed.id] = nil
        }
        return removed
    }

    func invalidate() {
        channel.invalidate()
    }

    private func attachFocusedWindow() -> AXWindow? {
        guard running.isActive, let window = focusedWindow(running) else { return nil }

        return attach(window).window
    }
}
