import CoreGraphics
import Foundation

/// Enrolls a window announced before it was on screen.
///
/// macOS posts the focus and creation notifications of a new window before the window is in
/// the on-screen list, so the on-screen check drops both and no later notification names the
/// window. The read is repeated for a moment to enroll it once it shows.
final class WindowEnrollment {
    private let windowSystem: WindowSystem
    private let workspaces: Workspaces
    private let placement: WindowPlacement
    private let backoff: Backoff

    private static let firstDelay: TimeInterval = 0.1
    private static let lastDelay: TimeInterval = 0.8

    init(
        windowSystem: WindowSystem,
        workspaces: Workspaces,
        placement: WindowPlacement,
        scheduleRetry: @escaping (TimeInterval, @escaping () -> Void) -> Void
    ) {
        self.windowSystem = windowSystem
        self.workspaces = workspaces
        self.placement = placement
        backoff = Backoff(schedule: scheduleRetry, first: Self.firstDelay, last: Self.lastDelay)
    }

    @discardableResult
    func enroll(_ win: WindowSnapshot, to workspace: Int) -> Int? {
        let placed = placement.assign(win, to: workspace)
        if placed == .refused(.retry) { enrollLater(win.id) }
        return placed.workspace
    }

    private func enrollLater(_ windowId: CGWindowID) {
        backoff.run { [weak self] in
            guard let self else { return true }

            return self.windowSystem.duringOperation("enroll-retry") {
                guard let win = self.windowSystem.snapshot(of: windowId) else { return true }

                return self.placement.assign(win, to: self.workspaces.current).workspace != nil
            }
        }
    }
}
