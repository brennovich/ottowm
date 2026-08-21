import AppKit

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

func axFrame(of window: AXUIElement) -> CGRect? {
    guard let rawPosition = attribute(window, kAXPositionAttribute),
          let rawSize = attribute(window, kAXSizeAttribute),
          CFGetTypeID(rawPosition) == AXValueGetTypeID(),
          CFGetTypeID(rawSize) == AXValueGetTypeID()
    else { return nil }

    var origin = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(rawPosition as! AXValue, .cgPoint, &origin),
          AXValueGetValue(rawSize as! AXValue, .cgSize, &size)
    else { return nil }

    return CGRect(origin: origin, size: size)
}

func windows(ofApplication pid: pid_t) -> [AXUIElement] {
    attribute(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AXUIElement] ?? []
}

func title(of window: AXUIElement) -> String? {
    attribute(window, kAXTitleAttribute) as? String
}
