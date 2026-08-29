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
    // swiftlint:disable force_cast
    guard AXValueGetValue(rawPosition as! AXValue, .cgPoint, &origin),
          AXValueGetValue(rawSize as! AXValue, .cgSize, &size)
    else { return nil }
    // swiftlint:enable force_cast

    return CGRect(origin: origin, size: size)
}

// Puts a window where a scene needs it, for a run that has to know the desk's geometry
// rather than take whatever macOS chose. The application may clamp or round what it is
// handed, so whoever cares about the outcome reads the frame back.
func setAXFrame(of window: AXUIElement, to frame: CGRect) {
    var origin = frame.origin
    var size = frame.size

    guard let position = AXValueCreate(.cgPoint, &origin),
          let dimensions = AXValueCreate(.cgSize, &size)
    else { fail("cannot build the AX values for \(frame)") }

    AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
    AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimensions)
}

func windows(ofApplication pid: pid_t) -> [AXUIElement] {
    attribute(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AXUIElement] ?? []
}

func title(of window: AXUIElement) -> String? {
    attribute(window, kAXTitleAttribute) as? String
}

// A named item of a named menu, pressable without the menu ever being opened, which is
// how the harness asks an application for something no command line flag offers.
func menuItem(ofApplication pid: pid_t, menu: String, named name: String) -> AXUIElement? {
    guard let bar = attribute(AXUIElementCreateApplication(pid), kAXMenuBarAttribute) else { return nil }

    // swiftlint:disable:next force_cast
    let menus = attribute(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement] ?? []
    guard let opened = menus.first(where: { title(of: $0) == menu }),
          let list = (attribute(opened, kAXChildrenAttribute) as? [AXUIElement])?.first
    else { return nil }

    return (attribute(list, kAXChildrenAttribute) as? [AXUIElement])?.first { title(of: $0) == name }
}

// The system wide element, built once: a benchmark reads its clock before the hotkey goes
// out, so anything built inside a probe is charged to the app as latency.
private let systemWide = AXUIElementCreateSystemWide()

// The focused window as the accessibility API reports it, rather than through
// NSWorkspace.frontmostApplication, which only updates when the main run loop runs. A
// measuring loop that polls without running it would read the same stale value until it
// gave up.
func systemFocusedWindow() -> AXUIElement? {
    guard let application = attribute(systemWide, kAXFocusedApplicationAttribute) else { return nil }
    // swiftlint:disable force_cast
    guard let window = attribute(application as! AXUIElement, kAXFocusedWindowAttribute) else { return nil }

    return (window as! AXUIElement)
    // swiftlint:enable force_cast
}
