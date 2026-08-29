import Foundation

/// Runs groups of work at the same time, on the threads the machine has.
enum Concurrently {
    /// Maps `body` over every group at once, and returns the results in the order the
    /// groups were given.
    ///
    /// `concurrentPerform` runs one of the groups on the calling thread and returns only
    /// once every group is done, so the caller waits the same way it waits for a loop.
    static func map<Element, Result>(over groups: [[Element]], _ body: ([Element]) -> [Result]) -> [Result] {
        guard groups.count > 1 else { return groups.first.map(body) ?? [] }

        var results = [[Result]](repeating: [], count: groups.count)
        results.withUnsafeMutableBufferPointer { buffer in
            DispatchQueue.concurrentPerform(iterations: groups.count) { index in
                buffer[index] = body(groups[index])
            }
        }

        return results.flatMap { $0 }
    }
}
