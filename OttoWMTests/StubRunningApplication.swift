import AppKit

final class StubRunningApplication: NSRunningApplication, @unchecked Sendable {
    private let pid: pid_t
    private let policy: NSApplication.ActivationPolicy
    private let name: String

    init(pid: pid_t, policy: NSApplication.ActivationPolicy = .regular, name: String = "App") {
        self.pid = pid
        self.policy = policy
        self.name = name
        super.init()
    }

    override var processIdentifier: pid_t { pid }
    override var activationPolicy: NSApplication.ActivationPolicy { policy }
    override var localizedName: String? { name }
}
