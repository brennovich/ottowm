import AppKit

// A tabbed window is made by merging windows that are already open rather than by asking
// for a new tab. Terminal answers `Shell > New Tab` with a submenu of profiles, and
// pressing either the parent or its first entry adds no tab; whether a new document opens
// as a tab at all is a system setting the run does not own. `Window > Merge All Windows`
// is a flat item in every application that tabs its windows, and it takes what is open.
//
// Merging takes every window the application has, so a desk staging more than one instance
// would merge across instances.
func mergeIntoTabs(ofApplication bundleId: String, named name: String) {
    guard let application = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else {
        fail("\(name) is not running, it has no windows to merge")
    }

    application.activate()

    guard let merge = menuItem(
        ofApplication: application.processIdentifier, menu: "Window", named: "Merge All Windows"
    ) else {
        fail("\(name) offers no Window > Merge All Windows, its windows cannot be made tabs of one")
    }

    let standing = windows(ofApplication: application.processIdentifier).count
    guard standing > 1 else { fail("\(name) has \(standing) window, there is nothing to merge it with") }

    AXUIElementPerformAction(merge, kAXPressAction as CFString)

    // Merged windows leave the list as they become tabs, only the one in front stays.
    eventually("\(name) merged its \(standing) windows into tabs") {
        let listed = windows(ofApplication: application.processIdentifier).count
        return listed == 1 ? nil : "\(name) still lists \(listed) windows"
    }
}

// The tab bar's buttons, one per tab. Only the tab in front carries the tab group, so a
// window read in the background answers none of them.
func tabButtons(of window: AXUIElement) -> [AXUIElement] {
    let children = attribute(window, kAXChildrenAttribute) as? [AXUIElement] ?? []

    for child in children where attribute(child, kAXRoleAttribute) as? String == kAXTabGroupRole {
        return (attribute(child, kAXChildrenAttribute) as? [AXUIElement] ?? [])
            .filter { attribute($0, kAXRoleAttribute) as? String == kAXRadioButtonRole }
    }

    return []
}

// Brings a tab to the front so a scene can read its frame. A tab that is not in front
// answers the frame the window had when that tab last was, and is not listed among the
// application's windows at all, so a check made on it without this reads a value that
// cannot change and passes on nothing. A frame written to a tab that is not in front is
// answered by that tab while the window stays where it is, so staging goes through this
// too, not only reading.
//
// The tab bar's button is pressed rather than a key combo posted: the run's own hotkeys go
// to whichever application is frontmost, and the scriptable way needs an Automation grant
// a machine with nobody at it never gets.
func bringTabToFront(_ window: AXUIElement, ofApplication bundleId: String, named name: String) {
    guard let application = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else {
        fail("\(name) is not running, its tab cannot be brought to the front")
    }
    guard let wanted = title(of: window) else { fail("the \(name) tab answers no title to find it in the tab bar by") }

    eventually("the \(name) tab \(wanted) is in front", announce: false) {
        let listed = windows(ofApplication: application.processIdentifier)
        guard !listed.contains(where: { CFEqual($0, window) }) else { return nil }

        guard let front = listed.first(where: { !tabButtons(of: $0).isEmpty }) else {
            return "\(name) shows no tabbed window"
        }
        guard let button = tabButtons(of: front).first(where: { title(of: $0) == wanted }) else {
            return "no tab titled \(wanted), the bar shows \(tabButtons(of: front).compactMap(title(of:)))"
        }

        AXUIElementPerformAction(button, kAXPressAction as CFString)

        return "pressed the \(wanted) tab"
    }
}
