/// A list of handlers that each receive every event reported.
struct Broadcast<Event> {
    private var handlers: [(watch: Int, handler: (Event) -> Void)] = []
    private var nextWatch = 0

    /// Returns the watch that `unwatch` takes.
    @discardableResult
    mutating func watch(_ handler: @escaping (Event) -> Void) -> Int {
        nextWatch += 1
        handlers.append((nextWatch, handler))
        return nextWatch
    }

    mutating func unwatch(_ watch: Int) {
        handlers.removeAll { $0.watch == watch }
    }

    func report(_ event: Event) {
        for (_, handler) in handlers { handler(event) }
    }
}
