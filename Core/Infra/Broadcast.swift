/// A list of handlers that each receive every event reported.
struct Broadcast<Event> {
    private var handlers: [(Event) -> Void] = []

    mutating func watch(_ handler: @escaping (Event) -> Void) {
        handlers.append(handler)
    }

    func report(_ event: Event) {
        for handler in handlers { handler(event) }
    }
}
