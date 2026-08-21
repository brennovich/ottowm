import ApplicationServices
import CoreGraphics

// Ceiling on how long a single AX round trip may block the caller.
let axMessagingTimeoutSeconds: Float = 0.1

// Undeclared by the AX headers, but supported by the applications we manage.
let FullScreenAttribute = "AXFullScreen"
let EnhancedUserInterfaceAttribute = "AXEnhancedUserInterface"
let TabGroupRole = "AXTabGroup"
let RadioButtonRole = "AXRadioButton"

// Swift cannot dynamically cast to a CoreFoundation type (`as? AXValue` always
// succeeds) so the type has to be checked by its CFTypeID.
func axValue(_ value: AnyObject?) -> AXValue? {
    guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    return (value as! AXValue)
}

// One attribute in one round trip. Failures are indistinguishable from an
// absent value here; callers that need the reason read the attribute themselves.
func axAttribute(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
    return value
}

// An element-valued attribute needs the same force cast as axValue, and for the
// same reason: `as? AXUIElement` succeeds for any type.
func axElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
    guard let value = axAttribute(element, attribute) else { return nil }
    return (value as! AXUIElement)
}

// Several attributes in one round trip. Attributes whose read failed are
// absent from the result.
func axAttributes(_ element: AXUIElement, _ attributes: [String]) -> [String: AnyObject] {
    var result: CFArray?
    let status = AXUIElementCopyMultipleAttributeValues(
        element, attributes as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &result
    )
    guard status == .success, let raw = result as? [AnyObject], raw.count == attributes.count else {
        return [:]
    }
    return Dictionary(uniqueKeysWithValues: zip(attributes, discardingAXErrors(raw)).compactMap { key, value in
        value.map { (key, $0) }
    })
}

func axPid(_ element: AXUIElement) -> pid_t? {
    var pid: pid_t = 0
    return AXUIElementGetPid(element, &pid) == .success ? pid : nil
}

// AXUIElementCopyMultipleAttributeValues reports a per-attribute failure inline,
// as an AXValue of type .axError, rather than failing the whole call.
func discardingAXErrors(_ values: [AnyObject]) -> [AnyObject?] {
    values.map { value in
        if let axValue = axValue(value), AXValueGetType(axValue) == .axError { return nil }
        return value
    }
}

func decodeCGPoint(_ value: AXValue) -> CGPoint? {
    guard AXValueGetType(value) == .cgPoint else { return nil }
    var point = CGPoint.zero
    return AXValueGetValue(value, .cgPoint, &point) ? point : nil
}

func decodeCGSize(_ value: AXValue) -> CGSize? {
    guard AXValueGetType(value) == .cgSize else { return nil }
    var size = CGSize.zero
    return AXValueGetValue(value, .cgSize, &size) ? size : nil
}

func encodeCGPoint(_ point: CGPoint) -> AXValue {
    var point = point
    return AXValueCreate(.cgPoint, &point)!
}

func encodeCGSize(_ size: CGSize) -> AXValue {
    var size = size
    return AXValueCreate(.cgSize, &size)!
}
