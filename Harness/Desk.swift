import AppKit

// An application the run opens a window in, and how to tell that window from the ones
// that were already there.
struct WindowSource {
    let name: String
    let bundleId: String
    let opens: URL
    let open: (URL) -> Void
    let titled: (String) -> Bool
}

private func launching(_ application: String) -> (URL) -> Void {
    { url in _ = shell("/usr/bin/open", ["-a", application, url.path]) }
}

// `open -a Safari` hands the page to the window that is already up rather than putting a
// new one up, and a tab that is not the active one cannot be read through the
// accessibility API, so the second desk's page opens and is unfindable at once. Safari is
// asked for the empty window first and handed the page after, because the page goes to
// whichever window is frontmost.
//
// Asked through the File menu rather than the scriptable way: pressing a menu item needs
// only the Accessibility permission this run already holds, where `make new document`
// needs an Automation grant that a machine with nobody at it never gets, and takes the
// two minute AppleEvent timeout to say so.
private func openSafariPage(_ url: URL) {
    if let safari = NSRunningApplication.runningApplications(withBundleIdentifier: safariBundleId).first {
        openEmptyWindow(of: safari)
    }

    launching("Safari")(url)
}

private func openEmptyWindow(of safari: NSRunningApplication) {
    safari.activate()

    guard let newWindow = menuItem(ofApplication: safari.processIdentifier, menu: "File", named: "New Window")
    else { fail("Safari offers no File > New Window, its page has no window of its own to open in") }

    let standing = windows(ofApplication: safari.processIdentifier).count
    AXUIElementPerformAction(newWindow, kAXPressAction as CFString)

    // Waited for rather than pressed and trusted: the page opens in whichever window is
    // frontmost, and the window this asked for arrives a moment after the press returns.
    eventually("Safari puts up an empty window", announce: false) {
        windows(ofApplication: safari.processIdentifier).count > standing ? nil : "still \(standing) windows"
    }
}

let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("ottowm-\(harness)-\(ProcessInfo.processInfo.processIdentifier)")
let stagedConfig = temporaryDirectory.appendingPathComponent("ottowm/ottowm")

// Stages the configuration the run is bound to and the documents its windows show, and
// returns the windows to open, the last one being the one the hotkeys move.
func stageDesk(instances: Int) -> [WindowSource] {
    do {
        try FileManager.default.createDirectory(
            at: stagedConfig.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        // The bundled defaults, read through XDG_CONFIG_HOME so whatever sits in the real
        // ~/.config/ottowm cannot change what this run is bound to.
        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: "\(appPath)/Contents/Resources/ottowm"),
            to: stagedConfig
        )
    } catch {
        fail("cannot stage the configuration, \(error.localizedDescription)")
    }

    cleanups.append { try? FileManager.default.removeItem(at: temporaryDirectory) }

    return (1...instances).flatMap(deskInstance)
}

// One desk: a file browser, a terminal, a browser and an editor, because a workspace
// switch costs what the windows standing on it cost. Everything it shows is named after
// this run and this instance, so every window carries a title no other window on the
// screen, nor any window of another instance, can answer to.
private func deskInstance(_ instance: Int) -> [WindowSource] {
    let stamp = "\(temporaryDirectory.lastPathComponent)-\(instance)"
    let directory = temporaryDirectory.appendingPathComponent(stamp)
    let page = temporaryDirectory.appendingPathComponent("\(stamp).html")
    let document = temporaryDirectory.appendingPathComponent("\(stamp).txt")
    let title = "OttoWM \(stamp)"

    guard (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil
    else { fail("cannot stage the desk directory \(directory.path)") }

    write("<!doctype html><html><head><title>\(title)</title></head><body>\(title)</body></html>", to: page)
    write(title, to: document)

    return [
        WindowSource(
            name: "Finder", bundleId: "com.apple.finder", opens: directory, open: launching("Finder")
        ) {
            $0 == stamp
        },
        WindowSource(
            name: "Terminal", bundleId: "com.apple.Terminal", opens: directory, open: launching("Terminal")
        ) {
            $0.contains(stamp)
        },
        WindowSource(name: "Safari", bundleId: safariBundleId, opens: page, open: openSafariPage) {
            $0 == title
        },
        WindowSource(
            name: "TextEdit", bundleId: "com.apple.TextEdit", opens: document, open: launching("TextEdit")
        ) {
            $0 == document.lastPathComponent
        },
    ]
}

// Each desk instance across the four quarters of the screen: Finder top left, Terminal
// bottom left, Safari top right and TextEdit bottom right. The centers are what the
// focus moves go by, so an application that clamps or rounds the frame it was handed
// stays in its quarter all the same, and the wait below reads the frame back to be sure.
func arrange(_ windows: [(String, String, AXUIElement)]) {
    let quarters = screenQuarters()

    for (index, (name, _, window)) in windows.enumerated() {
        let target = quarters[index % quarters.count].insetBy(dx: 10, dy: 10)

        // Written until it takes rather than once: a window that has just opened drops the
        // position write while it is still settling, Finder does. Checking only that the
        // window landed somewhere in its quarter passed over that, and left the run
        // asserting focus moves against a desk it had not arranged.
        eventually("\(name) sits in its quarter", announce: false) {
            setAXFrame(of: window, to: target)
            guard let frame = axFrame(of: window) else { return "\(name) reads no frame" }

            return frame.origin.equalTo(target.origin) ? nil : "\(name) at \(frame.origin), wanted \(target.origin)"
        }
    }
}

// Top left, bottom left, top right, bottom right, inset from the display edges so no
// window starts out under the menu bar nor at the hidden edge.
private func screenQuarters() -> [CGRect] {
    let bounds = CGDisplayBounds(CGMainDisplayID()).insetBy(dx: 40, dy: 60)
    let quarter = CGSize(width: bounds.width / 2, height: bounds.height / 2)

    return [
        CGRect(origin: CGPoint(x: bounds.minX, y: bounds.minY), size: quarter),
        CGRect(origin: CGPoint(x: bounds.minX, y: bounds.midY), size: quarter),
        CGRect(origin: CGPoint(x: bounds.midX, y: bounds.minY), size: quarter),
        CGRect(origin: CGPoint(x: bounds.midX, y: bounds.midY), size: quarter),
    ]
}

func write(_ contents: String, to url: URL) {
    guard (try? contents.write(to: url, atomically: true, encoding: .utf8)) != nil else {
        fail("cannot write \(url.path)")
    }
}

func openWindow(_ source: WindowSource, claimed: [AXUIElement]) -> AXUIElement {
    let wasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleId).isEmpty

    source.open(source.opens)

    var opened: AXUIElement?

    // An application that was already there belongs to whoever opened it, only the window
    // this run added goes away. One it launched itself goes away whole.
    cleanups.append {
        guard wasRunning else {
            NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleId)
                .forEach { $0.terminate() }
            return
        }
        guard let opened, let closeButton = attribute(opened, kAXCloseButtonAttribute) else { return }
        // swiftlint:disable:next force_cast
        AXUIElementPerformAction(closeButton as! AXUIElement, kAXPressAction as CFString)
    }

    let shows: () -> String? = {
        guard let application = NSRunningApplication
            .runningApplications(withBundleIdentifier: source.bundleId).first
        else { return "\(source.name) is not running" }

        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier else {
            return "\(source.name) is not frontmost, its window is not ready to be read"
        }

        opened = windows(ofApplication: application.processIdentifier)
            .first { window in
                !claimed.contains { CFEqual($0, window) } && source.titled(title(of: window) ?? "")
            }

        return opened == nil ? "no \(source.name) window titled after \(source.opens.lastPathComponent)" : nil
    }

    eventually("\(source.name) shows \(source.opens.lastPathComponent)", timeout: readyTimeout, shows)

    guard let opened else { fail("no \(source.name) window to drive") }

    return opened
}
