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

    let running: NSRunningApplication

    private let channel: AXNotifications
    private let subscription: Subscription
    private var attached: [AXUIElement: AXWindow] = [:]
    private var windowsById: [CGWindowID: AXWindow] = [:]

    var pid: pid_t { running.processIdentifier }
    var name: String { running.localizedName ?? "" }
    var windows: [AXWindow] { Array(attached.values) }

    init(_ running: NSRunningApplication, channel: AXNotifications) {
        self.running = running
        self.channel = channel
        self.subscription = .application(pid: running.processIdentifier, channel: channel)
    }

    func subscribe() -> Subscription.Outcome {
        subscription.activate()
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
}
