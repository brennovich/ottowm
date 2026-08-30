import ApplicationServices
import CoreGraphics

let axMessagingTimeoutSeconds: Float = 0.3

struct AXAttribute: Hashable, RawRepresentable {
    let rawValue: String

    static let children = AXAttribute(rawValue: kAXChildrenAttribute)
    static let closeButton = AXAttribute(rawValue: kAXCloseButtonAttribute)
    static let focusedWindow = AXAttribute(rawValue: kAXFocusedWindowAttribute)
    static let main = AXAttribute(rawValue: kAXMainAttribute)
    static let minimizeButton = AXAttribute(rawValue: kAXMinimizeButtonAttribute)
    static let minimized = AXAttribute(rawValue: kAXMinimizedAttribute)
    static let position = AXAttribute(rawValue: kAXPositionAttribute)
    static let role = AXAttribute(rawValue: kAXRoleAttribute)
    static let size = AXAttribute(rawValue: kAXSizeAttribute)
    static let subrole = AXAttribute(rawValue: kAXSubroleAttribute)
    static let windows = AXAttribute(rawValue: kAXWindowsAttribute)

    static let fullScreen = AXAttribute(rawValue: "AXFullScreen")
    static let enhancedUserInterface = AXAttribute(rawValue: "AXEnhancedUserInterface")
}

struct AXRole: Hashable, RawRepresentable {
    let rawValue: String

    static let standardWindow = AXRole(rawValue: kAXStandardWindowSubrole)

    static let tabGroup = AXRole(rawValue: "AXTabGroup")
    static let radioButton = AXRole(rawValue: "AXRadioButton")

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init?(_ value: AnyObject?) {
        guard let name = value as? String else { return nil }
        self.init(rawValue: name)
    }
}

/// The AX notification channel of one process. `AXObserver` delivers every
/// notification subscribed through it to one callback, so the AX machinery is not
/// leaked to the callers.
///
/// The callback is held by a `CallbackBox`, the only way to pass it to the C
/// callback function AX calls when a notification arrives.
struct AXNotifications {
    let subscribe: (AXUIElement, String) -> AXError
    let invalidate: () -> Void

    static func of(pid: pid_t, callback: @escaping (AXUIElement, String) -> Void) -> AXNotifications? {
        var observer: AXObserver?
        guard AXObserverCreate(pid, axObserverCallback, &observer) == .success, let observer else {
            return nil
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        let box = Unmanaged.passRetained(CallbackBox(callback))

        return AXNotifications(
            subscribe: { element, notification in
                let result = trace(.subscribe, notification) {
                    AXObserverAddNotification(observer, element, notification as CFString, box.toOpaque())
                }
                if result == .success || result == .notificationAlreadyRegistered { return .success }

                Log.observer.error("addNotification \(notification) failed pid=\(pid) err=\(result.rawValue)")
                return result
            },
            invalidate: {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
                box.release()
            }
        )
    }
}

private final class CallbackBox {
    let callback: (AXUIElement, String) -> Void

    init(_ callback: @escaping (AXUIElement, String) -> Void) {
        self.callback = callback
    }
}

private func axObserverCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }

    // Rebuilds the Unmanaged from the raw pointer
    let box = Unmanaged<CallbackBox>.fromOpaque(refcon).takeUnretainedValue()
    box.callback(element, notification as String)
}

extension AXUIElement {
    func value(of attribute: AXAttribute) -> AnyObject? {
        var value: CFTypeRef?
        let status = trace(.read, attribute.rawValue) {
            AXUIElementCopyAttributeValue(self, attribute.rawValue as CFString, &value)
        }
        guard status == .success else { return nil }
        return value
    }

    func values(of attributes: [AXAttribute]) -> [AXAttribute: AnyObject] {
        var result: CFArray?
        let status = trace(.read, attributes.map(\.rawValue).joined(separator: "+")) {
            AXUIElementCopyMultipleAttributeValues(
                self, attributes.map(\.rawValue) as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &result
            )
        }
        guard status == .success, let raw = result as? [AnyObject], raw.count == attributes.count else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: zip(attributes, raw.discardingAXErrors).compactMap { key, value in
            value.map { (key, $0) }
        })
    }

    func elementValue(of attribute: AXAttribute) -> AXUIElement? {
        guard let value = value(of: attribute) else { return nil }
        // swiftlint:disable:next force_cast
        return (value as! AXUIElement)
    }

    func setValue(_ point: CGPoint, for attribute: AXAttribute) -> AXError {
        setValue(point.axValue, for: attribute)
    }

    func setValue(_ size: CGSize, for attribute: AXAttribute) -> AXError {
        setValue(size.axValue, for: attribute)
    }

    func setValue(_ flag: Bool, for attribute: AXAttribute) -> AXError {
        setValue(flag ? kCFBooleanTrue! : kCFBooleanFalse!, for: attribute)
    }

    private func setValue(_ value: CFTypeRef, for attribute: AXAttribute) -> AXError {
        trace(.write, attribute.rawValue) {
            AXUIElementSetAttributeValue(self, attribute.rawValue as CFString, value)
        }
    }
}

extension Array where Element == AnyObject {
    var discardingAXErrors: [AnyObject?] {
        map { value in
            if let axValue = checkedAXValue(value), AXValueGetType(axValue) == .axError { return nil }
            return value
        }
    }
}

extension CGPoint {
    var axValue: AXValue {
        var point = self
        return AXValueCreate(.cgPoint, &point)!
    }

    init?(axValue value: AnyObject?) {
        guard let value = checkedAXValue(value), AXValueGetType(value) == .cgPoint else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value, .cgPoint, &point) else { return nil }
        self = point
    }
}

extension CGSize {
    var axValue: AXValue {
        var size = self
        return AXValueCreate(.cgSize, &size)!
    }

    init?(axValue value: AnyObject?) {
        guard let value = checkedAXValue(value), AXValueGetType(value) == .cgSize else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value, .cgSize, &size) else { return nil }
        self = size
    }
}

private func checkedAXValue(_ value: AnyObject?) -> AXValue? {
    guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    // swiftlint:disable:next force_cast
    return (value as! AXValue)
}
