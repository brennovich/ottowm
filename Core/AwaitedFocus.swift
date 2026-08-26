import CoreGraphics

/// Tracks the focus OttoWM last requested, and the earlier requests it replaced before their
/// notification arrived. macOS delivers a notification for a replaced request anyway, and by
/// then a switch may have parked that window, so the notification looks like the user focusing
/// a parked window.
struct AwaitedFocus {
    private var current: CGWindowID?
    private var superseded: Set<CGWindowID> = []

    mutating func request(_ windowId: CGWindowID) {
        if let current, current != windowId { superseded.insert(current) }
        current = windowId
    }

    /// Takes the notification for `windowId` as the answer to a request.
    /// - Returns: `true` if it answers a request that was already replaced.
    mutating func settle(_ windowId: CGWindowID) -> Bool {
        let isEcho = superseded.remove(windowId) != nil

        if current == windowId {
            current = nil
            superseded = []
        }
        return isEcho
    }

    mutating func forget(_ windowId: CGWindowID) {
        if current == windowId { current = nil }
        superseded.remove(windowId)
    }
}
