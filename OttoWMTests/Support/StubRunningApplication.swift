import AppKit

final class StubRunningApplication: NSRunningApplication, @unchecked Sendable {
    var hasFinishedLaunching: Bool
    var activated = true

    private let pid: pid_t
    private let policy: NSApplication.ActivationPolicy
    private let name: String
    private let bundleId: String?

    init(
        pid: pid_t,
        policy: NSApplication.ActivationPolicy = .regular,
        name: String = "App",
        bundleId: String? = "com.example.app",
        hasFinishedLaunching: Bool = true
    ) {
        self.pid = pid
        self.policy = policy
        self.name = name
        self.bundleId = bundleId
        self.hasFinishedLaunching = hasFinishedLaunching
        super.init()
    }

    override var processIdentifier: pid_t { pid }
    override var activationPolicy: NSApplication.ActivationPolicy { policy }
    override var localizedName: String? { name }
    override var bundleIdentifier: String? { bundleId }
    override var isFinishedLaunching: Bool { hasFinishedLaunching }
    override var isActive: Bool { activated }
}
