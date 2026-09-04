import CoreGraphics
import Foundation

/// macOS posts the focus and creation notifications of a new window before the window is
/// in the on-screen list, so the on-screen check drops both, and no later notification
/// names the window. The read is repeated for a moment to enroll it once it shows.
final class WindowEnrollment {
    private let windowSystem: WindowSystem
    private let workspaces: Workspaces
    private let managed: ManagedWindows
    private let scheduleRetry: (TimeInterval, @escaping () -> Void) -> Void

    private static let firstDelay: TimeInterval = 0.1
    private static let lastDelay: TimeInterval = 0.8

    init(
        windowSystem: WindowSystem,
        workspaces: Workspaces,
        managed: ManagedWindows,
        scheduleRetry: @escaping (TimeInterval, @escaping () -> Void) -> Void
    ) {
        self.windowSystem = windowSystem
        self.workspaces = workspaces
        self.managed = managed
        self.scheduleRetry = scheduleRetry
    }

    @discardableResult
    func enroll(_ win: WindowSnapshot, to workspace: Int) -> Int? {
        let assigned = managed.assign(win, to: workspace)
        if assigned == nil { enrollLater(win) }
        return assigned
    }

    func enrollLater(_ win: WindowSnapshot) {
        guard win.isAdmissible else { return }
        retry(win.id, in: Self.firstDelay)
    }

    private func retry(_ windowId: CGWindowID, in delay: TimeInterval) {
        guard delay <= Self.lastDelay else { return }

        scheduleRetry(delay) { [weak self] in
            guard let self else { return }

            self.windowSystem.duringOperation("enroll-retry") {
                guard let win = self.windowSystem.snapshot(of: windowId) else { return }

                if self.managed.assign(win, to: self.workspaces.current) == nil {
                    self.retry(windowId, in: delay * 2)
                }
            }
        }
    }
}
