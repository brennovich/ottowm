import ApplicationServices

// Ceiling on how long a single AX round trip may block the caller.
let axMessagingTimeoutSeconds: Float = 0.5

// Swift cannot dynamically cast to a CoreFoundation type (`as? AXValue` always
// succeeds) so the type has to be checked by its CFTypeID.
func axValue(_ value: AnyObject?) -> AXValue? {
    guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    return (value as! AXValue)
}

// AXUIElementCopyMultipleAttributeValues reports a per-attribute failure inline,
// as an AXValue of type .axError, rather than failing the whole call.
func discardingAXErrors(_ values: [AnyObject]) -> [AnyObject?] {
    values.map { value in
        if let axValue = axValue(value), AXValueGetType(axValue) == .axError { return nil }
        return value
    }
}
