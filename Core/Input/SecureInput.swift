import Foundation

/// The window server's secure event input flag, which apps set while a password field has
/// focus. While it is set, no keyboard event is delivered to any event tap.
struct SecureInput {
    private static let skyLight = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
    private static let symbol = "SLSIsSecureEventInputSet"

    func isActive() -> Bool {
        SecureInput.skyLightSymbol()?() == true
    }

    /// `kCGSSessionSecureInputPID` from the IO registry is not read alongside this: it records
    /// the last process to set the flag and is not cleared on release, so it can name a process
    /// that already exited while another one holds the flag.
    ///
    /// The handle stays open, since closing it can unload the framework the pointer belongs to.
    private static func skyLightSymbol() -> (() -> Bool)? {
        guard let handle = dlopen(skyLight, RTLD_LAZY),
              let address = dlsym(handle, symbol) else { return nil }

        let isSet = unsafeBitCast(address, to: (@convention(c) () -> Bool).self)

        return isSet
    }
}
