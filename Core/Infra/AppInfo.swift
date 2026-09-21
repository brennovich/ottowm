import Foundation

enum AppInfo {
    static func version(_ bundle: Bundle = .main) -> String {
        bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    static func build(_ bundle: Bundle = .main) -> String {
        bundle.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    }
}
