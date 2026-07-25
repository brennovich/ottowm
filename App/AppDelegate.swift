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
    }
}
