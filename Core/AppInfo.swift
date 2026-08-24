import Foundation

enum AppInfo {
    /// Read from the bundle so MARKETING_VERSION, which `make bump` writes, stays the only
    /// place a version is spelled out.
    static func version(_ bundle: Bundle = .main) -> String {
        bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }
}
