import QuartzCore

extension CATransaction {
    /// Runs `body` in a transaction with implicit animations off.
    static func withoutActions<T>(_ body: () -> T) -> T {
        begin()
        setDisableActions(true)
        defer { commit() }
        return body()
    }
}
