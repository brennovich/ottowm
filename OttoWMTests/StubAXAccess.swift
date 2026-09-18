import AppKit
import ApplicationServices
import CoreGraphics

final class StubAXAccess {
    var attributes: [AXUIElement: [AXAttribute: AnyObject]] = [:]
    var statuses: [AXUIElement: AXError] = [:]
    var windowIds: [AXUIElement: CGWindowID] = [:]
    var frontmost: NSRunningApplication?

    // The start scan reads the applications on several threads at once, so what it
    // records is read and written from all of them.
    private let lock = NSLock()
    private var recordedReads: [(element: AXUIElement, attributes: [AXAttribute])] = []
    private var recordedWindowIdReads: [AXUIElement] = []
    private var recordedWrites: [(element: AXUIElement, attribute: AXAttribute, value: AnyObject)] = []
    private var recordedActions: [(element: AXUIElement, action: String)] = []
    private var recordedActivations: [NSRunningApplication] = []
    private var nextElementToken: pid_t = 5000

    var writes: [(element: AXUIElement, attribute: AXAttribute, value: AnyObject)] { locked { recordedWrites } }
    var actions: [(element: AXUIElement, action: String)] { locked { recordedActions } }
    var activations: [NSRunningApplication] { locked { recordedActivations } }

    func reads(of element: AXUIElement) -> [[AXAttribute]] {
        locked { recordedReads.filter { $0.element == element }.map(\.attributes) }
    }

    func reads(of attribute: AXAttribute, on element: AXUIElement) -> Int {
        reads(of: element).filter { $0.contains(attribute) }.count
    }

    func windowIdReads(of element: AXUIElement) -> Int {
        locked { recordedWindowIdReads.filter { $0 == element }.count }
    }

    lazy var access = AXAccess(
        copyValue: { element, attribute in
            self.locked { self.recordedReads.append((element, [attribute])) }
            if let status = self.statuses[element] { return (status, nil) }
            guard let value = self.attributes[element]?[attribute] else { return (.noValue, nil) }
            return (.success, value)
        },
        values: { element, attributes in
            self.locked { self.recordedReads.append((element, attributes)) }
            guard self.statuses[element] == nil else { return [:] }
            return (self.attributes[element] ?? [:]).filter { attributes.contains($0.key) }
        },
        setValue: { element, attribute, value in
            self.locked { self.recordedWrites.append((element, attribute, value)) }
            if let status = self.statuses[element] { return status }
            self.attributes[element, default: [:]][attribute] = value
            return .success
        },
        perform: { element, action in
            self.locked { self.recordedActions.append((element, action)) }
            return self.statuses[element] ?? .success
        },
        windowId: { element in
            self.locked { self.recordedWindowIdReads.append(element) }
            if let status = self.statuses[element] { return (status, 0) }
            guard let id = self.windowIds[element] else { return (.failure, 0) }
            return (.success, id)
        },
        activate: { app in
            self.locked { self.recordedActivations.append(app) }
            return true
        },
        frontmostApplication: { self.frontmost }
    )

    func makeElement() -> AXUIElement {
        let element = AXUIElementCreateApplication(nextElementToken)
        nextElementToken += 1
        return element
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
