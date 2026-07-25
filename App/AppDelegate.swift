import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
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
    }
}
