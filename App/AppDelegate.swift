import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    private let windowObserver = AXWindowObserver()
    private let hotkeys = HotkeyEventTap()
    private var engine: Engine?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        )

        print("OttoWM (\(AppInfo.version)) launched")
        print("\t Accessibility status: \(trusted)")

        let windowById: (CGWindowID) -> AXWindow? = { [windowObserver] id in
            windowObserver.allWindows().first { $0.id == id }
        }

        let space = VirtualSpace(
            screen: MainScreen(),
            window: windowById,
            allWindows: { [windowObserver] in windowObserver.allWindows() },
            onScreenWindowIds: { Self.onScreenWindowIds() },
            managedWindowIds: { [weak self] in self?.engine?.managedWindowIds ?? [] },
            focusedWindow: { AXWindow.focused() }
        )

        let engine = Engine(
            space: space,
            window: windowById,
            focusedWindow: { AXWindow.focused() }
        )
        self.engine = engine

        engine.start(windows: windowObserver.allWindows())
        windowObserver.start { engine.handle($0) }

        let hotkeysStarted = hotkeys.start { action in
            switch action {
            case let .switchToVirtualSpace(virtualSpace):
                engine.switchToVirtualSpace(virtualSpace)
            case let .moveWindowToVirtualSpace(virtualSpace):
                engine.moveWindowToVirtualSpace(nil, virtualSpace)
            }
        }
        print("\t Hotkeys: \(hotkeysStarted ? "active" : "event tap creation failed (check Accessibility permission)")")
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
