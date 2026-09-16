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
        guard let loginSession else { return }

        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Content(loginSession: loginSession, state: state)).write(to: url, options: .atomic)
        } catch {
            Log.state.error("cannot write \(url.path): \(error)")
        }
    }

    /// The key is not documented. The window server draws a new UUID at every login.
    private static func currentLoginSession() -> String? {
        (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionUniqueSessionUUID"] as? String
    }
}
