/// Each read behind this cache is an IPC round trip (the focused window, the
/// on-screen window list), and a single engine operation asks for it several
/// times. Holds one read for the duration of an operation and drops it when the
/// outermost one ends.
final class OperationCache<Value> {
    private let read: () -> Value
    private var cached: Value?
    private var operationDepth = 0

    init(_ read: @escaping () -> Value) {
        self.read = read
    }

    func value() -> Value {
        if let cached { return cached }

        let value = read()
        if operationDepth > 0 { cached = value }
        return value
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
