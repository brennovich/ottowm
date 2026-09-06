import CoreGraphics

/// The frame each maximized window is to go back to. Recording the frame the window came
/// from, rather than the one it was given, keeps the original through a second maximize at
/// another inset. Tabs of one window share the record: they stand at one frame, and every
/// tab holds the frame so closing the one the maximize went through leaves the rest with it.
final class MaximizedWindows {
    private let tabs: (CGWindowID) -> [CGWindowID]

    private var maximized: [CGWindowID: CGRect] = [:]

    init(tabs: @escaping (CGWindowID) -> [CGWindowID]) {
        self.tabs = tabs
    }

    func restoringFrame(of windowId: CGWindowID) -> CGRect? {
        tabs(windowId).lazy.compactMap { self.maximized[$0] }.first
    }

    /// A tab that joins a maximized window takes the frame its siblings go back to: the
    /// tabs the maximize recorded can all close while this one stays.
    func shareFrame(with windowId: CGWindowID) {
        maximized[windowId] = restoringFrame(of: windowId)
    }

    func record(_ outcomes: [FrameOutcome]) {
        for outcome in outcomes {
            switch outcome {
            case let .maximized(windowId, from): keep(restoringFrame(of: windowId) ?? from, of: windowId)
            case let .active(windowId): forget(windowId)
            case .parked, .gone: continue
            }
        }
    }

    /// A destroyed window has already left its tab group by the time it is forgotten, so
    /// the tabs that stay keep the frame.
    func forget(_ windowId: CGWindowID) {
        for tabId in tabs(windowId) { maximized[tabId] = nil }
    }

    private func keep(_ frame: CGRect, of windowId: CGWindowID) {
        for tabId in tabs(windowId) { maximized[tabId] = frame }
    }
}
