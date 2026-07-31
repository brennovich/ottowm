import CoreGraphics
import Foundation

// Taking a system window-list snapshot is an IPC round trip, and a single engine
// operation asks which windows are on screen several times. Holds one snapshot for
// the duration of an operation and drops it when the outermost one ends.
final class OnScreenWindows {
    private let snapshot: () -> Set<CGWindowID>
    private var cached: Set<CGWindowID>?
    private var operationDepth = 0

    init(snapshot: @escaping () -> Set<CGWindowID>) {
        self.snapshot = snapshot
    }

    func ids() -> Set<CGWindowID> {
        if let cached { return cached }

        let ids = snapshot()
        if operationDepth > 0 { cached = ids }
        return ids
    }

    func duringOperation<T>(_ body: () throws -> T) rethrows -> T {
        operationDepth += 1
        defer {
            operationDepth -= 1
            if operationDepth == 0 { cached = nil }
        }
        return try body()
    }
}

func onScreenWindowIds(from windowInfoList: [[String: Any]]) -> Set<CGWindowID> {
    var ids: Set<CGWindowID> = []
    for info in windowInfoList {
        if let number = info[kCGWindowNumber as String] as? NSNumber {
            ids.insert(CGWindowID(number.uint32Value))
        }
    }
    return ids
}
