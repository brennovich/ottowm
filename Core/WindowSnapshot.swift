import CoreGraphics

// A window's state at a point in time, read in one batched round trip to reduce IPC calls.
struct WindowSnapshot: Sendable, Equatable {
    let id: CGWindowID
    let appName: String
    let isStandard: Bool
    let isFullScreen: Bool
    let isMinimized: Bool
    let tabCount: Int
    let frame: CGRect
}

extension WindowSnapshot {
    var logDescription: String { "id=\(id) app=\(appName)" }

    func moved(to frame: CGRect) -> WindowSnapshot {
        WindowSnapshot(
            id: id,
            appName: appName,
            isStandard: isStandard,
            isFullScreen: isFullScreen,
            isMinimized: isMinimized,
            tabCount: tabCount,
            frame: frame
        )
    }
}
