import Darwin
import Dispatch

/// Every way the process ends. A parked window sits at the hidden edge, and the frame it
/// belongs at is only held in memory, so it must be restored before the process exits.
final class Shutdown {
    private let stop: () -> Void
    private let exit: (Int32) -> Void
    private let observeSIGTERM: (@escaping () -> Void) -> (any DispatchSourceSignal)?
    private var termination: (any DispatchSourceSignal)?

    init(
        stop: @escaping () -> Void,
        exit: @escaping (Int32) -> Void = { Darwin.exit($0) },
        observeSIGTERM: @escaping (@escaping () -> Void) -> (any DispatchSourceSignal)? = Shutdown.sigterm
    ) {
        self.stop = stop
        self.exit = exit
        self.observeSIGTERM = observeSIGTERM
    }

    /// The `quit` action. Restores nothing: `Engine.handle(.quit)` calls `Engine.stop`
    /// first.
    func quit() {
        Log.app.notice("quit action received, window frames restored")
        exit(EXIT_SUCCESS)
    }

    /// The default action for SIGTERM ends the process with every parked window still at
    /// the hidden edge.
    func startWatchingSIGTERM() {
        termination = observeSIGTERM { [stop, exit] in
            Log.app.notice("SIGTERM received, restoring window frames")
            stop()
            exit(EXIT_SUCCESS)
        }
    }

    private static func sigterm(_ handler: @escaping () -> Void) -> (any DispatchSourceSignal)? {
        signal(SIGTERM, SIG_IGN)

        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler(handler: handler)
        source.resume()

        return source
    }
}
