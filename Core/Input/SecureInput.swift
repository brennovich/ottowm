import Foundation

/// The window server's secure event input flag, which apps set while a password field has
/// focus. While it is set, no keyboard event is delivered to any event tap.
final class SecureInput {
    private static let symbol = "SLSIsSecureEventInputSet"
    private static let registerSymbol = "SLSRegisterNotifyProc"
    /// The window server posts 752 when the flag is set and 753 when it is cleared. Both are private and
    /// were read off a run that registered every type: a macOS update can renumber them.
    private static let notificationTypes: [UInt32] = [752, 753]

    private typealias IsSet = @convention(c) () -> Bool
    private typealias NotifyProc = @convention(c) (UInt32, UnsafeMutableRawPointer?, UInt32, UnsafeMutableRawPointer?) -> Void
    private typealias Register = @convention(c) (NotifyProc, UInt32, UnsafeMutableRawPointer?) -> Int32

    private var subscribers = Broadcast<Bool>()
    private var isRegistered = false

    /// `kCGSSessionSecureInputPID` from the IO registry is not read alongside this: it records
    /// the last process to set the flag and is not cleared on release, so it can name a process
    /// that already exited while another one holds the flag.
    func isActive() -> Bool {
        SkyLight.symbol(Self.symbol, as: IsSet.self)?() == true
    }

    /// Reports the flag now and on every change, on the main thread, until the returned closure is called. Repeats
    /// are not filtered: the flag is read again on each notification rather than taken from its type.
    @discardableResult
    func startWatching(_ handler: @escaping (Bool) -> Void) -> () -> Void {
        let watch = subscribers.watch(handler)
        handler(isActive())
        if !isRegistered {
            isRegistered = true
            register()
        }
        return { [weak self] in self?.subscribers.unwatch(watch) }
    }

    /// The registration is never taken back, so it owns this instance: the callback reads it through the context
    /// pointer, which outlives every other reference.
    private func register() {
        guard let register = SkyLight.symbol(Self.registerSymbol, as: Register.self) else {
            return Log.hotkey.error("SLSRegisterNotifyProc is missing, changes of secure event input are not reported")
        }

        let context = Unmanaged.passRetained(self).toOpaque()
        let notify: NotifyProc = { _, _, _, context in
            guard let context else { return }

            let secureInput = Unmanaged<SecureInput>.fromOpaque(context).takeUnretainedValue()
            secureInput.subscribers.report(secureInput.isActive())
        }
        for type in Self.notificationTypes where register(notify, type, context) != 0 {
            Log.hotkey.error("SLSRegisterNotifyProc rejected type \(type), that change of secure event input is not reported")
        }
    }
}
