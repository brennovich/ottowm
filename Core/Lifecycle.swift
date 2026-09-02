import AppKit
import Darwin
import Dispatch

final class Lifecycle {
    private let stop: () -> Void
    private let resume: () -> Void
    private let screenLock: ScreenLock
    private let exit: (Int32) -> Void
    private let launchNewInstance: (@escaping () -> Void) -> Void
    private let observeSIGTERM: (@escaping () -> Void) -> (any DispatchSourceSignal)?
    private var termination: (any DispatchSourceSignal)?

    var screenIsLocked: Bool { screenLock.isLocked }

    init(
        stop: @escaping () -> Void,
        resume: @escaping () -> Void,
        screenLock: ScreenLock = ScreenLock(),
        exit: @escaping (Int32) -> Void = { Darwin.exit($0) },
        launchNewInstance: @escaping (@escaping () -> Void) -> Void = Lifecycle.newInstance,
        observeSIGTERM: @escaping (@escaping () -> Void) -> (any DispatchSourceSignal)? = Lifecycle.sigterm
    ) {
        self.stop = stop
        self.resume = resume
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
