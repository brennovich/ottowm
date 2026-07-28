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

    mutating func register(_ element: Element, pid: pid_t, id: CGWindowID) {
        refs[element] = WindowRef(pid: pid, id: id)
    }

    mutating func removeWindow(for element: Element) -> CGWindowID? {
        refs.removeValue(forKey: element)?.id
    }

    mutating func evict(pid: pid_t) {
        refs = refs.filter { $0.value.pid != pid }
    }

    func unregistered(of elements: [Element]) -> [Element] {
        elements.filter { refs[$0] == nil }
    }

    func element(for id: CGWindowID) -> (element: Element, pid: pid_t)? {
        refs.first { $0.value.id == id }.map { ($0.key, $0.value.pid) }
    }
}
