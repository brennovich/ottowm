import Foundation

enum AppInfo {
    static func version(_ bundle: Bundle = .main) -> String {
        bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }
}
