import AppKit

// Terminal shows the tab bar only while a window has more than one tab, and the bar takes
// the height it needs out of the window: a window merged into tabs ends up tens of points
// from where it was read before the merge. With the bar already up, every window the run
// stages keeps its frame through the merge. The menu item is named `Hide Tab Bar` once the
// bar is up, so a session that already shows it finds nothing to press and nothing to undo.
func showTabBar(ofApplication bundleId: String, named name: String) {
    guard let application = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else {
        fail("\(name) is not running, its tab bar cannot be shown")
    }

    application.activate()

    guard let show = menuItem(
        ofApplication: application.processIdentifier, menu: "View", named: "Show Tab Bar"
    ) else { return }

    AXUIElementPerformAction(show, kAXPressAction as CFString)
    report("ok, \(name) shows the tab bar")
}

// A tabbed window is made by merging windows that are already open rather than by asking
// for a new tab. Terminal's `Shell > New Tab` opens a submenu of profiles, and pressing
// either the parent or its first entry adds no tab; whether a new document opens as a tab
// at all is a system setting the run does not own. `Window > Merge All Windows` is a flat
// item in every application that tabs its windows, and it merges what is already open.
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
// window read in the background reports none of them.
func tabButtons(of window: AXUIElement) -> [AXUIElement] {
    let children = attribute(window, kAXChildrenAttribute) as? [AXUIElement] ?? []

    for child in children where attribute(child, kAXRoleAttribute) as? String == kAXTabGroupRole {
        return (attribute(child, kAXChildrenAttribute) as? [AXUIElement] ?? [])
            .filter { attribute($0, kAXRoleAttribute) as? String == kAXRadioButtonRole }
    }

    return []
}

// Brings a tab to the front so a scene can read its frame. A tab that is not in front
// reports the frame the window had when that tab last was, and is not listed among the
// application's windows at all, so a check made on it without this reads a value that
// cannot change. A frame written to a tab that is not in front is reported back by that
// tab while the window stays where it is, so staging goes through this too, not only
// reading.
//
// The tab bar's buttons are pressed in turn rather than the one belonging to this window
// picked out of them: Terminal titles its buttons after the process running in each tab,
// which is `-zsh` for every tab of a desk this run staged. The right tab is in front when
// the application lists this window, not when the bar says so.
//
// Pressed rather than a key combo posted: the run's own hotkeys go to whichever application
// is frontmost, and the scriptable way needs an Automation grant a machine with nobody at
// it never gets.
func bringTabToFront(_ window: AXUIElement, ofApplication bundleId: String, named name: String) {
    guard let application = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else {
        fail("\(name) is not running, its tab cannot be brought to the front")
    }

    let pid = application.processIdentifier
    guard !isListed(window, of: pid) else { return }

    guard let tabbed = windows(ofApplication: pid).first(where: { !tabButtons(of: $0).isEmpty }) else {
        fail("\(name) shows no tabbed window to bring the \(name) tab out of")
    }

    // Read again on every press: the tab group belongs to the window in front, and the one
    // that goes behind takes its own tab bar with it.
    for index in 0 ..< tabButtons(of: tabbed).count {
        guard let front = windows(ofApplication: pid).first(where: { !tabButtons(of: $0).isEmpty }) else { break }

        let buttons = tabButtons(of: front)
        guard index < buttons.count else { break }

        AXUIElementPerformAction(buttons[index], kAXPressAction as CFString)

        if waitUntilListed(window, of: pid) {
            report("ok, \(name) is the tab in front")
            return
        }
    }

    fail("none of \(name)'s tabs brought the window the run claimed to the front")
}

// Whether this window is the one its application lists, which for a tabbed window is the
// tab in front.
private func isListed(_ window: AXUIElement, of pid: pid_t) -> Bool {
    windows(ofApplication: pid).contains { CFEqual($0, window) }
}

// Polls for a tab switch, and reports whether it landed rather than ending the run: the
// caller has other tabs to try.
private func waitUntilListed(_ window: AXUIElement, of pid: pid_t) -> Bool {
    let deadline = Date().addingTimeInterval(tabSwitchTimeout)

    repeat {
        if isListed(window, of: pid) { return true }
        RunLoop.current.run(until: Date().addingTimeInterval(pollInterval))
    } while Date() < deadline

    return false
}
