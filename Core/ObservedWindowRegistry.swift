import CoreGraphics

// Pure bookkeeping behind AXWindowObserver: which AX elements are already
// watched for destruction, and which window id each one maps to once the
// element itself can no longer answer (a destroyed element has no attributes).
struct ObservedWindowRegistry<Element: Hashable> {
    private struct WindowRef {
        let pid: pid_t
        let id: CGWindowID
    }

    private var refs: [Element: WindowRef] = [:]
    private var elementsById: [CGWindowID: Element] = [:]

    mutating func register(_ element: Element, pid: pid_t, id: CGWindowID) {
        if let previous = refs[element] {
            removeReverse(previous.id, element)
        }
        refs[element] = WindowRef(pid: pid, id: id)
        elementsById[id] = element
    }

    mutating func removeWindow(for element: Element) -> CGWindowID? {
        guard let ref = refs.removeValue(forKey: element) else { return nil }
        removeReverse(ref.id, element)
        return ref.id
    }

    mutating func evict(pid: pid_t) {
        for (element, ref) in refs where ref.pid == pid {
            refs[element] = nil
            removeReverse(ref.id, element)
        }
    }

    func unregistered(of elements: [Element]) -> [Element] {
        elements.filter { refs[$0] == nil }
    }

    func element(for id: CGWindowID) -> (element: Element, pid: pid_t)? {
        guard let element = elementsById[id], let ref = refs[element] else { return nil }
        return (element, ref.pid)
    }

    private mutating func removeReverse(_ id: CGWindowID, _ element: Element) {
        if elementsById[id] == element { elementsById[id] = nil }
    }
}
