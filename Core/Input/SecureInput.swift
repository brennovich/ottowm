import Foundation

/// The window server's secure event input flag, which apps set while a password field has
/// focus. While it is set, no keyboard event is delivered to any event tap, so a tap that
/// reports itself enabled still sees nothing.
struct SecureInput {
    private static let skyLight = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
    private static let symbol = "SLSIsSecureEventInputSet"

    var lookUp: () -> (() -> Bool)? = SecureInput.skyLightSymbol

    /// - Returns: whether the flag is set, or `nil` when SkyLight no longer exports the symbol.
    func isSet() -> Bool? {
        lookUp()?()
    }

    /// - Returns: what to report while keystrokes stop at the window server, or `nil` while
    ///   they reach event taps.
    func warning() -> String? {
        guard isSet() == true else { return nil }

        return "secure event input is set by another app, no keystroke reaches the event tap"
    }

    /// `kCGSSessionSecureInputPID` from the IO registry is not read alongside this: it records
    /// the last process to set the flag and is not cleared on release, so it can name a process
    /// that already exited while another one holds the flag.
    ///
    /// The handle stays open, since closing it can unload the framework the pointer belongs to.
    private static func skyLightSymbol() -> (() -> Bool)? {
        guard let handle = dlopen(skyLight, RTLD_LAZY), let address = dlsym(handle, symbol) else { return nil }

        let isSet = unsafeBitCast(address, to: (@convention(c) () -> Bool).self)

        return isSet
    }
}
