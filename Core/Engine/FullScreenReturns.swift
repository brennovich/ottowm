import CoreGraphics
import Foundation

/// A window leaving full screen comes back to the desktop without a notification that
/// names it. The focus event macOS does send can arrive while the window is still in
/// transition, and it is dropped then, so every later event is another chance to notice
/// the window is back.
final class FullScreenReturns {
    private let windowSystem: WindowSystem
    private let workspaces: Workspaces
    private let managed: ManagedWindows
    private let navigation: Navigation
    private let scheduleRetry: (TimeInterval, @escaping () -> Void) -> Void

    private static let firstDelay: TimeInterval = 0.1
    private static let lastDelay: TimeInterval = 1.6

    init(
        windowSystem: WindowSystem,
        workspaces: Workspaces,
        managed: ManagedWindows,
        navigation: Navigation,
        scheduleRetry: @escaping (TimeInterval, @escaping () -> Void) -> Void
    ) {
        self.windowSystem = windowSystem
        self.workspaces = workspaces
        self.managed = managed
        self.navigation = navigation
        self.scheduleRetry = scheduleRetry
    }

    @discardableResult
    func follow() -> Bool {
        for (windowId, workspace) in workspaces.fullScreenWindows {
            guard let win = windowSystem.snapshot(of: windowId),
                  managed.followBackFromFullScreen(win, to: workspace)
            else { continue }

            // The window is back, but the focus can sit on a window this switch just parked.
            navigation.restore()
            return true
        }
        return false
    }

    /// The window can still read as full screen when the Space change announcing its return
    /// arrives, and macOS sends no notification once it settles: the desktop can stay quiet
    /// until the user acts. The check is repeated for a few seconds to catch that.
    func followWithRetries() {
        followWithRetries(in: Self.firstDelay)
    }

    private func followWithRetries(in delay: TimeInterval) {
        guard !follow(), !workspaces.fullScreenWindows.isEmpty, delay <= Self.lastDelay else { return }

        scheduleRetry(delay) { [weak self] in
            guard let self else { return }

            self.windowSystem.duringOperation("full-screen-return") {
                self.followWithRetries(in: delay * 2)
            }
        }
    }
}
