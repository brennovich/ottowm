import Foundation

enum XDGDirectory {
    /// - Returns: the directory `variable` names, or `fallback` under the home directory when
    ///   the variable is unset or empty. A leading `~/` is expanded.
    static func url(_ variable: String, orHome fallback: String, environment: [String: String]) -> URL {
        func value(_ name: String) -> String? { environment[name].flatMap { $0.isEmpty ? nil : $0 } }

        let home = value("HOME") ?? NSHomeDirectory()
        let directory = value(variable) ?? "\(home)/\(fallback)"
        return URL(fileURLWithPath: directory.hasPrefix("~/") ? home + directory.dropFirst() : directory)
    }
}
