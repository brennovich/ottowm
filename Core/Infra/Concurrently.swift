import Foundation

enum Concurrently {
    static func map<Element, Result>(_ elements: [Element], _ body: (Element) -> Result) -> [Result] {
        guard elements.count > 1 else { return elements.map(body) }

        var results: [Result?] = Array(repeating: nil, count: elements.count)
        results.withUnsafeMutableBufferPointer { buffer in
            DispatchQueue.concurrentPerform(iterations: elements.count) { index in
                buffer[index] = body(elements[index])
            }
        }

        return results.map { $0! }
    }
}
