import CoreGraphics
import Foundation

final class WindowSystem {
    private let focusedWindow: OperationCache<WindowSnapshot?>
    private let onScreenWindows: OperationCache<[CGWindowID: CGRect]>
    private let window: (CGWindowID) -> (any Window)?
    private let roundTrips: RoundTrips
    private let owns: (CGRect) -> Bool

    init(
        focusedWindow: OperationCache<WindowSnapshot?>,
        onScreenWindows: OperationCache<[CGWindowID: CGRect]>,
        window: @escaping (CGWindowID) -> (any Window)?,
        roundTrips: RoundTrips = .shared,
        owns: @escaping (CGRect) -> Bool = { _ in true }
    ) {
        self.focusedWindow = focusedWindow
        self.onScreenWindows = onScreenWindows
        self.window = window
        self.roundTrips = roundTrips
        self.owns = owns
    }

    /// A copy whose focused and on-screen reads leave out the windows whose frame `owns`
    /// rejects. It shares the reads of this one, so an operation still makes each read once.
    /// The reads of one window by id are not filtered.
    func scoped(_ owns: @escaping (CGRect) -> Bool) -> WindowSystem {
        WindowSystem(
            focusedWindow: focusedWindow,
            onScreenWindows: onScreenWindows,
            window: window,
            roundTrips: roundTrips,
            owns: owns
        )
    }

    func duringOperation<T>(_ name: StaticString, _ body: () -> T) -> T {
        roundTrips.duringOperation(name) {
            onScreenWindows.duringOperation { focusedWindow.duringOperation(body) }
        }
    }

    func focused() -> WindowSnapshot? {
        focusedWindow.value().flatMap { owns($0.frame) ? $0 : nil }
    }

    func shows(_ windowId: CGWindowID) -> Bool {
        onScreenWindows.value()[windowId].map(owns) ?? false
    }

    func showsAny(_ windowIds: Set<CGWindowID>) -> Bool {
        windowIds.contains(where: shows)
    }

    func frames(of windowIds: [CGWindowID]) -> [CGWindowID: CGRect] {
        let onScreen = onScreenWindows.value()
        return windowIds.reduce(into: [:]) { frames, windowId in
            frames[windowId] = onScreen[windowId].flatMap { owns($0) ? $0 : nil }
        }
    }

    func snapshot(of windowId: CGWindowID) -> WindowSnapshot? {
        window(windowId)?.snapshot()
    }

    func frame(of windowId: CGWindowID) -> CGRect? {
        window(windowId)?.movableFrame()
    }

    /// Reads the windows in parallel: a read right after a size write waits for the
    /// application's relayout. The windows are looked up on the calling thread.
    func readFrames(of windowIds: [CGWindowID]) -> [CGWindowID: CGRect] {
        let windows = windowIds.compactMap { windowId in window(windowId).map { (id: windowId, window: $0) } }
        let frames = Concurrently.map(windows) { $0.window.movableFrame() }
        return zip(windows, frames).reduce(into: [:]) { result, pair in result[pair.0.id] = pair.1 }
    }

    func tabCount(of windowId: CGWindowID) -> Int {
        window(windowId)?.tabCount() ?? 1
    }
}
