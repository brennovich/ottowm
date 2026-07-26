import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    private let windowObserver = AXWindowObserver()
    private var virtualSpace: VirtualSpace?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        )

        print("OttoWM (\(AppInfo.version)) launched")
        print("\t Accessibility status: \(trusted)")

        let mainScreen = MainScreen()
        print("\t MainScreen \(mainScreen.uuid ?? "unknown"): \(mainScreen.visibleFrame)")

        if let window = AXWindow.focused() {
            print("\t Focused window \(window.id) [\(window.appName)]: \(window.frame)")
            print("\t\t standard: \(window.isStandard), fullScreen: \(window.isFullScreen), minimized: \(window.isMinimized), tabs: \(window.tabCount)")
        } else {
            print("\t Focused window: none")
        }

        let windows = windowObserver.allWindows()
        print("\t allWindows (\(windows.count)):")
        for window in windows {
            print("\t\t \(window.id) [\(window.appName)]: \(window.frame)")
        }

        windowObserver.start { event in
            switch event {
            case let .created(window):
                print("event created \(window.id) [\(window.appName)]: \(window.frame)")
            case let .focused(window):
                print("event focused \(window.id) [\(window.appName)]: \(window.frame)")
            case let .destroyed(id):
                print("event destroyed \(id)")
            }
        }

        smokeTestVirtualSpace(on: mainScreen)
    }

    // Temporary Step 6 smoke harness: exercise the concrete VirtualSpace on the real
    // display. Removed once Step 7 wires the Engine.
    private func smokeTestVirtualSpace(on screen: Screen) {
        let space = VirtualSpace(
            screen: screen,
            window: { [weak self] id in self?.windowObserver.allWindows().first { $0.id == id } },
            allWindows: { [weak self] in self?.windowObserver.allWindows() ?? [] },
            onScreenWindowIds: { Self.onScreenWindowIds() },
            managedWindowIds: { [weak self] in Set((self?.windowObserver.allWindows() ?? []).map(\.id)) },
            focusedWindow: { AXWindow.focused() }
        )
        virtualSpace = space

        space.setupForMainScreen()
        space.startWatchingForManualNavigation { placement in
            print("event manual-navigation -> \(placement)")
        }

        let target = AXWindow.focused() ?? windowObserver.allWindows().first {
            $0.id != 0 && $0.isStandard && $0.appName != "Finder"
        }
        guard let target else {
            print("smoke: no target window found")
            return
        }

        let id = target.id
        print("\t smoke target \(id) [\(target.appName)]: \(target.frame)")
        print("\t isOnManagedSpace: \(space.isOnManagedSpace()), managesWindow(\(id)): \(space.managesWindow(id))")

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            print("smoke: hiding \(id) to the corner nub")
            space.moveWindowToSpace(id, .storage)
            print("smoke: windowSpaces(\(id)) = \(space.windowSpaces(id))")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                print("smoke: restoring \(id) to its saved frame")
                space.moveWindowToSpace(id, .active)
            }
        }
    }

    private static func onScreenWindowIds() -> Set<CGWindowID> {
        guard let infoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        var ids: Set<CGWindowID> = []
        for info in infoList {
            if let number = info[kCGWindowNumber as String] as? NSNumber {
                ids.insert(CGWindowID(number.uint32Value))
            }
        }
        return ids
    }
}
