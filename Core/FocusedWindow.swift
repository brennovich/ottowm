import CoreGraphics

final class FocusedWindow {
    private let read: () -> WindowSnapshot?
    private var cached: WindowSnapshot??
    private var operationDepth = 0

    init(_ read: @escaping () -> WindowSnapshot?) {
        self.read = read
    }

    func snapshot() -> WindowSnapshot? {
        if let cached { return cached }

        let snapshot = read()
        if operationDepth > 0 { cached = snapshot }
        return snapshot
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
