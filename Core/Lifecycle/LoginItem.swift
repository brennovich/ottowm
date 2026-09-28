import ServiceManagement

/// OttoWM as a login item of the user. macOS reports the state, so a change made in System Settings shows here.
/// `SMAppService` exists from macOS 13; earlier systems report `.unavailable` and ignore writes.
enum LoginItem {
    enum State: Equatable {
        case on
        case off
        /// Registered, but turned off by the user in System Settings → General → Login Items.
        case needsApproval
        case unavailable
    }

    static func state() -> State {
        guard #available(macOS 13, *) else { return .unavailable }

        return State(SMAppService.mainApp.status)
    }

    static func set(_ on: Bool) throws {
        guard #available(macOS 13, *) else { return }

        if on {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSettings() {
        guard #available(macOS 13, *) else { return }

        SMAppService.openSystemSettingsLoginItems()
    }
}

extension LoginItem.State {
    @available(macOS 13, *)
    init(_ status: SMAppService.Status) {
        switch status {
        case .enabled: self = .on
        case .requiresApproval: self = .needsApproval
        case .notRegistered, .notFound: self = .off
        @unknown default: self = .off
        }
    }
}
