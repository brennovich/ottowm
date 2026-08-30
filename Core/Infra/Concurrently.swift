import Foundation

enum Concurrently {
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
