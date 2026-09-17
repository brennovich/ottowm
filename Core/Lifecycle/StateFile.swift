import CoreGraphics
import Foundation

/// The file OttoWM saves its state to after every operation and reads at launch. A state
/// saved in another login session is ignored: its window ids name other windows.
struct StateFile {
    private struct Content: Codable {
        let loginSession: String
        let state: SavedState
    }

    let url: URL
    private let loginSession: String?

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        loginSession: String? = Self.currentLoginSession()
    ) {
        url = XDGDirectory.url("XDG_STATE_HOME", orHome: ".local/state", environment: environment)
            .appendingPathComponent("ottowm/state.json")
        self.loginSession = loginSession
    }

    func load() -> SavedState? {
        guard let data = try? Data(contentsOf: url) else {
            Log.state.info("no state at \(url.path)")
            return nil
        }

        do {
            let content = try JSONDecoder().decode(Content.self, from: data)
            guard content.loginSession == loginSession else {
                Log.state.info("\(url.path) was saved in another login session, starting without it")
                return nil
            }
            return content.state
        } catch {
            Log.state.error("cannot read \(url.path), starting without it: \(error)")
            return nil
        }
    }

    func save(_ state: SavedState) {
        guard let loginSession else {
            Log.state.error("cannot read the login session, not writing \(url.path)")
            return
        }

        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Content(loginSession: loginSession, state: state)).write(to: url, options: .atomic)
        } catch {
            Log.state.error("cannot write \(url.path): \(error)")
        }
    }

    /// The kernel gives each login a new audit session id and restarts the count at boot, so the id
    /// is paired with the boot time.
    static func currentLoginSession() -> String? {
        var auditInfo = auditinfo_addr_t()
        guard getaudit_addr(&auditInfo, Int32(MemoryLayout<auditinfo_addr_t>.size)) == 0 else { return nil }

        var bootTime = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &bootTime, &size, nil, 0) == 0 else { return nil }

        return "\(auditInfo.ai_asid)-\(bootTime.tv_sec).\(bootTime.tv_usec)"
    }
}
