import AppKit

// Opens a sheet on the window an application has in front. An application showing a sheet
// reports the sheet as its focused window, and the sheet is not in its window list. Page
// Setup is a flat item of the File menu of every document application, and nothing it
// changes is saved unless its OK button is pressed.
func showPageSetupSheet(ofApplication bundleId: String, named name: String) -> AXUIElement {
    guard let application = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else {
        fail("\(name) is not running, it cannot show a sheet")
    }

    application.activate()

    guard let pageSetup = menuItem(ofApplication: application.processIdentifier, menu: "File", named: "Page Setup…") else {
        fail("\(name) offers no File > Page Setup…, it cannot show a sheet")
    }

    AXUIElementPerformAction(pageSetup, kAXPressAction as CFString)

    var sheet: AXUIElement?
    eventually("\(name) shows the Page Setup sheet") {
        sheet = focusedSheet(of: application.processIdentifier)
        return sheet == nil ? "\(name) has no sheet focused" : nil
    }

    guard let sheet else { fail("\(name) shows no sheet") }
    return sheet
}

// Pressed rather than Escape posted: the run's own key events go to whichever application
// is frontmost.
func dismissSheet(_ sheet: AXUIElement, ofApplication bundleId: String, named name: String) {
    guard let cancel = descendant(of: sheet, titled: "Cancel") else { fail("\(name)'s sheet offers no Cancel button") }
    guard let application = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else {
        fail("\(name) is not running, its sheet cannot be dismissed")
    }

    AXUIElementPerformAction(cancel, kAXPressAction as CFString)

    eventually("\(name) dismissed the sheet") {
        focusedSheet(of: application.processIdentifier) == nil ? nil : "\(name) still shows the sheet"
    }
}

private func focusedSheet(of pid: pid_t) -> AXUIElement? {
    guard let focused = attribute(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute) else { return nil }
    // swiftlint:disable:next force_cast
    let window = focused as! AXUIElement

    return attribute(window, kAXRoleAttribute) as? String == kAXSheetRole ? window : nil
}

private func descendant(of element: AXUIElement, titled name: String) -> AXUIElement? {
    for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
        if title(of: child) == name { return child }
        if let found = descendant(of: child, titled: name) { return found }
    }
    return nil
}
