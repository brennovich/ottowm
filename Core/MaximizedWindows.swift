import CoreGraphics

/// The frame each maximized window is to go back to. Recording the frame the window came
/// from, rather than the one it was given, keeps the original through a second maximize at
/// another inset. Tabs of one window share the record: they stand at one frame, and a tab
/// opened while the window is maximized brings none of its own.
final class MaximizedWindows {
    private let tabs: (CGWindowID) -> [CGWindowID]

    private var maximized: [CGWindowID: CGRect] = [:]

    init(tabs: @escaping (CGWindowID) -> [CGWindowID]) {
        self.tabs = tabs
    }

    func restoringFrame(of windowId: CGWindowID) -> CGRect? {
        tabs(windowId).lazy.compactMap { self.maximized[$0] }.first
    }

    func record(_ outcomes: [FrameOutcome]) {
        for outcome in outcomes {
            switch outcome {
            case let .maximized(windowId, from): maximized[windowId] = restoringFrame(of: windowId) ?? from
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
}
