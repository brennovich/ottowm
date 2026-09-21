import AppKit
import ApplicationServices

/// Where the About window reads each value from. The defaults are the app's; tests replace them.
struct StatusSources {
    var version: () -> String = { AppInfo.version() }
    var build: () -> String = { AppInfo.build() }
    var system: () -> String = {
        #if arch(arm64)
        let chip = "Apple Silicon"
        #else
        let chip = "Intel"
        #endif
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion) · \(chip)"
    }
    var isTrusted: () -> Bool = { AXIsProcessTrusted() }
    var hotkeysListening: () -> Bool
    var secureInputHeld: () -> Bool
    var display: () -> String
    var configPath: () -> URL = { ConfigFile.path() }
    var configExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    var createConfig: () -> Void = { ConfigFile.writeDefaults() }
    var configError: () -> ConfigError?
    var readSetting: (String, String) -> Bool? = Requirements.read
}
