import AppKit

/// The Pager of each display, and the sources that make them check whether a window covers their tab.
final class Pagers {
    private let windowFrames: () -> [CGWindowID: CGRect]
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void
    private var pagers: [DisplayID: Pager] = [:]
    private var secureInputIsActive = false
    private var checkScheduled = false
    private var checkCount = 0
    private var observers: [NSObjectProtocol] = []

    var isEnabled = false {
        didSet {
            for pager in pagers.values { pager.isEnabled = isEnabled }
        }
    }

    /// `schedule` delays the check by 50ms: without the delay, the main queue runs a check between two window events of one
    /// workspace switch, and a switch between two workspaces that both cover the tab starts a restore and turns it back.
    init(
        startWatchingWindows: (@escaping (WindowEvent) -> Void) -> Void,
        windowFrames: @escaping () -> [CGWindowID: CGRect],
        startWatchingSecureInput: (@escaping (Bool) -> Void) -> Void,
        schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void = {
            DispatchQueue.main.asyncAfter(deadline: .now() + $0, execute: $1)
        },
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.windowFrames = windowFrames
        self.schedule = schedule
        startWatchingWindows { [weak self] _ in self?.scheduleCheck() }
        startWatchingSecureInput { [weak self] active in
            guard let self else { return }

            secureInputIsActive = active
            for pager in pagers.values { pager.secureInputChanged(active) }
        }
        // Hiding an application reports no window event.
        observers = [NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification].map {
            notificationCenter.addObserver(forName: $0, object: nil, queue: .main) { [weak self] _ in self?.scheduleCheck() }
        }
    }

    func add(_ pager: Pager, on displayId: DisplayID) {
        pager.requestCheck = { [weak self] in self?.scheduleCheck() }
        pager.secureInputChanged(secureInputIsActive)
        pager.isEnabled = isEnabled
        pagers[displayId] = pager
    }

    /// The Pager is held until it has slid out: its panels are ordered out in a completion that holds them weakly.
    func remove(on displayId: DisplayID) {
        guard let pager = pagers.removeValue(forKey: displayId) else { return }

        pager.dismiss { _ = pager }
    }

    /// `done` runs once, after every Pager has slid out.
    func dismiss(then done: @escaping () -> Void) {
        var sliding = pagers.count
        guard sliding > 0 else { return done() }

        for pager in pagers.values {
            pager.dismiss {
                sliding -= 1
                if sliding == 0 { done() }
            }
        }
    }

    /// The events of one change join the check the first of them scheduled.
    private func scheduleCheck() {
        guard !checkScheduled else { return }

        checkScheduled = true
        schedule(0.05) { [weak self] in
            guard let self else { return }

            checkScheduled = false
            guard isEnabled else { return }

            check()
            checkCount += 1
            // Some applications (Ghostty) update the window list up to 130ms after they report a new frame.
            // A newer check drops this recheck, since its own recheck reads the list later.
            let count = checkCount
            schedule(0.13) { [weak self] in
                guard let self, checkCount == count else { return }

                check()
            }
        }
    }

    private func check() {
        let frames = windowFrames()
        for pager in pagers.values { pager.check(against: frames) }
    }
}
