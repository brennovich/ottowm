import ApplicationServices
import CoreGraphics

/// Ceiling on how long a single AX round trip may block the caller.
let axMessagingTimeoutSeconds: Float = 0.3

/// The name of an accessibility attribute.
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

    // Undeclared by the AX headers, but supported by the applications OttoWM manages.
    static let fullScreen = AXAttribute(rawValue: "AXFullScreen")
    static let enhancedUserInterface = AXAttribute(rawValue: "AXEnhancedUserInterface")
}

/// The value of an element's `role` or `subrole` attribute.
struct AXRole: Hashable, RawRepresentable {
    let rawValue: String

    static let standardWindow = AXRole(rawValue: kAXStandardWindowSubrole)

    // Undeclared by the AX headers.
    static let tabGroup = AXRole(rawValue: "AXTabGroup")
    static let radioButton = AXRole(rawValue: "AXRadioButton")

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Reads a role out of an attribute value.
    /// - Returns: `nil` if the value is absent or is not a string.
    init?(_ value: AnyObject?) {
        guard let name = value as? String else { return nil }
        self.init(rawValue: name)
    }
}

extension AXUIElement {
    /// Reads one attribute in one round trip.
    ///
    /// A failed read is indistinguishable from an absent value. A caller that needs the
    /// reason reads the attribute itself.
    func value(of attribute: AXAttribute) -> AnyObject? {
        var value: CFTypeRef?
        let status = RoundTrips.shared.measure(.read, attribute.rawValue) {
            AXUIElementCopyAttributeValue(self, attribute.rawValue as CFString, &value)
        }
        guard status == .success else { return nil }
        return value
    }

    /// Reads several attributes in one round trip.
    /// - Returns: the values that were read; an attribute whose read failed is absent.
    func values(of attributes: [AXAttribute]) -> [AXAttribute: AnyObject] {
        var result: CFArray?
        let status = RoundTrips.shared.measure(.read, attributes.map(\.rawValue).joined(separator: "+")) {
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

    /// Reads an element-valued attribute in one round trip.
    func elementValue(of attribute: AXAttribute) -> AXUIElement? {
        // The same force cast as checkedAXValue(_:), and for the same reason: `as? AXUIElement`
        // succeeds for any type.
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
        RoundTrips.shared.measure(.write, attribute.rawValue) {
            AXUIElementSetAttributeValue(self, attribute.rawValue as CFString, value)
        }
    }
}

extension Array where Element == AnyObject {
    /// The values with the failed reads replaced by `nil`.
    ///
    /// `AXUIElementCopyMultipleAttributeValues` reports a per-attribute failure inline,
    /// as an `AXValue` of type `.axError`, rather than failing the whole call.
    var discardingAXErrors: [AnyObject?] {
        map { value in
            if let axValue = checkedAXValue(value), AXValueGetType(axValue) == .axError { return nil }
            return value
        }
    }
}

extension CGPoint {
    /// The box the accessibility API takes a point in.
    var axValue: AXValue {
        var point = self
        return AXValueCreate(.cgPoint, &point)!
    }

    /// Reads a point out of an attribute value.
    /// - Returns: `nil` if the value is absent or does not box a point.
    init?(axValue value: AnyObject?) {
        guard let value = checkedAXValue(value), AXValueGetType(value) == .cgPoint else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value, .cgPoint, &point) else { return nil }
        self = point
    }
}

extension CGSize {
    /// The box the accessibility API takes a size in.
    var axValue: AXValue {
        var size = self
        return AXValueCreate(.cgSize, &size)!
    }

    /// Reads a size out of an attribute value.
    /// - Returns: `nil` if the value is absent or does not box a size.
    init?(axValue value: AnyObject?) {
        guard let value = checkedAXValue(value), AXValueGetType(value) == .cgSize else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value, .cgSize, &size) else { return nil }
        self = size
    }
}

/// Swift cannot dynamically cast to a CoreFoundation type (`as? AXValue` always succeeds)
/// so the type has to be checked by its CFTypeID.
private func checkedAXValue(_ value: AnyObject?) -> AXValue? {
    guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    // swiftlint:disable:next force_cast
    return (value as! AXValue)
}
