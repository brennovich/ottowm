import AppKit
import ApplicationServices
import CoreGraphics

// The map of known windows: AXUIElement <-> CGWindowID plus pid -> application.
final class WindowRegistry {
    private struct WindowRef {
        let pid: pid_t
        let id: CGWindowID
    }

    private var refs: [AXUIElement: WindowRef] = [:]
    private var elementsById: [CGWindowID: AXUIElement] = [:]
    private var applications: [pid_t: NSRunningApplication] = [:]

    func window(byId id: CGWindowID) -> AXWindow? {
        guard let (element, pid) = element(for: id),
              let app = applications[pid]
        else { return nil }
        return AXWindow(element: element, application: app, id: id)
    }

    func add(_ app: NSRunningApplication) {
        applications[app.processIdentifier] = app
    }

    func register(_ element: AXUIElement, pid: pid_t, id: CGWindowID) {
        if let previous = refs[element] {
            removeReverse(previous.id, element)
        }
        refs[element] = WindowRef(pid: pid, id: id)
        elementsById[id] = element
    }

    func removeWindow(for element: AXUIElement) -> CGWindowID? {
        guard let ref = refs.removeValue(forKey: element) else { return nil }
        removeReverse(ref.id, element)
        return ref.id
    }

    func evict(pid: pid_t) {
        applications[pid] = nil
        for (element, ref) in refs where ref.pid == pid {
            refs[element] = nil
            removeReverse(ref.id, element)
        }
    }

    func knows(_ element: AXUIElement) -> Bool {
        refs[element] != nil
    }

    func knownWindows() -> [(element: AXUIElement, id: CGWindowID)] {
        refs.map { (element: $0.key, id: $0.value.id) }
    }

    func unregistered(of elements: [AXUIElement]) -> [AXUIElement] {
        elements.filter { !knows($0) }
    }

    func element(for id: CGWindowID) -> (element: AXUIElement, pid: pid_t)? {
        guard let element = elementsById[id], let ref = refs[element] else { return nil }
        return (element, ref.pid)
    }

    private func removeReverse(_ id: CGWindowID, _ element: AXUIElement) {
        if elementsById[id] == element { elementsById[id] = nil }
    }
}
