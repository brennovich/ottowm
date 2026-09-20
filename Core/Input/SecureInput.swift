import Foundation

/// The window server's secure event input flag, which apps set while a password field has
/// focus. While it is set, no keyboard event is delivered to any event tap.
final class SecureInput {
    private static let skyLight = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
    private static let symbol = "SLSIsSecureEventInputSet"
    private static let registerSymbol = "SLSRegisterNotifyProc"
    /// The window server posts 752 when the flag is set and 753 when it is cleared. Both are private and
    /// were read off a run that registered every type: a macOS update can renumber them.
    private static let notificationTypes: [UInt32] = [752, 753]

    private typealias IsSet = @convention(c) () -> Bool
    private typealias NotifyProc = @convention(c) (UInt32, UnsafeMutableRawPointer?, UInt32, UnsafeMutableRawPointer?) -> Void
    private typealias Register = @convention(c) (NotifyProc, UInt32, UnsafeMutableRawPointer?) -> Int32

    private var handler: ((Bool) -> Void)?

    /// `kCGSSessionSecureInputPID` from the IO registry is not read alongside this: it records
    /// the last process to set the flag and is not cleared on release, so it can name a process
    /// that already exited while another one holds the flag.
    func isActive() -> Bool {
        Self.skyLightSymbol(Self.symbol, as: IsSet.self)?() == true
    }

    /// Reports the flag now and on every change, on the main thread. Repeats are not filtered: the flag is read
    /// again on each notification rather than taken from its type.
    ///
    /// The watch is never taken back, so the registration owns this instance: the callback reads it through the
    /// context pointer, which outlives every other reference.
    func startWatching(_ handler: @escaping (Bool) -> Void) {
        self.handler = handler
        handler(isActive())

        guard let register = Self.skyLightSymbol(Self.registerSymbol, as: Register.self) else {
            return Log.hotkey.error("SLSRegisterNotifyProc is missing, changes of secure event input are not reported")
        }

        let context = Unmanaged.passRetained(self).toOpaque()
        let notify: NotifyProc = { _, _, _, context in
            guard let context else { return }

            let secureInput = Unmanaged<SecureInput>.fromOpaque(context).takeUnretainedValue()
            secureInput.handler?(secureInput.isActive())
        }
        for type in Self.notificationTypes where register(notify, type, context) != 0 {
            Log.hotkey.error("SLSRegisterNotifyProc rejected type \(type), that change of secure event input is not reported")
        }
    }

    /// The handle stays open, since closing it can unload the framework the pointer belongs to.
    private static func skyLightSymbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle = dlopen(skyLight, RTLD_LAZY),
              let address = dlsym(handle, name) else { return nil }

        return unsafeBitCast(address, to: type)
    }
}
