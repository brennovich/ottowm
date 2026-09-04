import AppKit
import Darwin
import Dispatch

final class Lifecycle {
    private let stop: () -> Void
    private let resume: () -> Void
    private let reloadBindings: () -> ConfigError?
    private let ask: (ConfigError) -> ConfigAlert.Response
    private let screenLock: ScreenLock
    private let exit: (Int32) -> Void
    private let launchNewInstance: (@escaping () -> Void) -> Void
    private let observeSIGTERM: (@escaping () -> Void) -> (any DispatchSourceSignal)?
    private var termination: (any DispatchSourceSignal)?
    private var awaitingUserInput = false

    var screenIsLocked: Bool { screenLock.isLocked }

    init(
        stop: @escaping () -> Void,
        resume: @escaping () -> Void,
        reloadBindings: @escaping () -> ConfigError?,
        ask: @escaping (ConfigError) -> ConfigAlert.Response = { ConfigAlert.ask($0, .reload) },
        screenLock: ScreenLock = ScreenLock(),
        exit: @escaping (Int32) -> Void = { Darwin.exit($0) },
        launchNewInstance: @escaping (@escaping () -> Void) -> Void = Lifecycle.newInstance,
        observeSIGTERM: @escaping (@escaping () -> Void) -> (any DispatchSourceSignal)? = Lifecycle.sigterm
    ) {
        self.stop = stop
        self.resume = resume
        self.reloadBindings = reloadBindings
        self.ask = ask
        self.screenLock = screenLock
        self.exit = exit
        self.launchNewInstance = launchNewInstance
        self.observeSIGTERM = observeSIGTERM
    }

    func quit() {
        Log.app.notice("quit action received, restoring window frames")
        stop()
        exit(EXIT_SUCCESS)
    }

    /// The event tap stays live while the alert is up, and the main queue is drained in
    /// `NSModalPanelRunLoopMode`, so another restart press reaches reload during the modal.
    ///
    /// Without the guard it stacks a second alert on the first.
    func reload() {
        guard !awaitingUserInput else { return }
        guard let error = reloadBindings() else { return }

        awaitingUserInput = true
        let response = ask(error)
        awaitingUserInput = false

        guard response == .restart else { return }

        Log.app.notice("config rejected, relaunching")
        relaunch()
    }

    func relaunch() {
        Log.app.notice("relaunching, restoring window frames")
        stop()
        launchNewInstance { [exit] in exit(EXIT_SUCCESS) }
    }

    func startWatchingScreenLock() {
        screenLock.startWatching(unlocked: resume)
    }

    func startWatchingSIGTERM() {
        termination = observeSIGTERM { [stop, exit] in
            Log.app.notice("SIGTERM received, restoring window frames")
            stop()
            exit(EXIT_SUCCESS)
        }
    }

    private static func newInstance(_ launched: @escaping () -> Void) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL, configuration: configuration
        ) { _, _ in launched() }
    }

    private static func sigterm(_ handler: @escaping () -> Void) -> (any DispatchSourceSignal)? {
        signal(SIGTERM, SIG_IGN)

        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler(handler: handler)
        source.resume()

        return source
    }
}
