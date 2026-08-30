import AppKit
import ApplicationServices
import CoreGraphics

final class Application {
    let running: NSRunningApplication

    private let channel: AXNotifications
    private let subscription: Subscription
    private var attached: Set<AXWindow> = []
    private var windowsById: [CGWindowID: AXWindow] = [:]

    var pid: pid_t { running.processIdentifier }
    var name: String { running.localizedName ?? "" }
    var windows: [AXWindow] { Array(attached) }

    init(_ running: NSRunningApplication, channel: AXNotifications) {
        self.running = running
        self.channel = channel
        self.subscription = .application(pid: running.processIdentifier, channel: channel)
    }

    func subscribe() -> Subscription.Outcome {
        subscription.activate()
    }

    @discardableResult
    func attach(_ window: AXWindow) -> AXWindow? {
        guard !attached.contains(window), window.id != 0 else { return nil }

        Subscription.window(window, channel: channel).activate()
        attached.insert(window)
        windowsById[window.id] = window

        Log.windows.info("subscribing \(window.logDescription)")
        return window
    }

    func findWindow(_ window: AXWindow) -> AXWindow? {
        attached.firstIndex(of: window).map { attached[$0] }
    }

    func findWindow(by id: CGWindowID) -> AXWindow? {
        windowsById[id]
    }

    func detach(_ window: AXWindow) -> AXWindow? {
        guard let removed = findWindow(window) else { return nil }

        attached.remove(removed)
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
