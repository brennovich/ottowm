import AppKit

/// The tab in the bottom right corner with the current workspace, and the masks that round the other three screen corners.
/// The tab retracts while a window overlaps it, and the cue pulses under it while an app holds secure event input.
final class Pager {
    private let tab = PagerTabView()
    private let tabPanel: any Panel
    private let cue = CueView()
    private let cuePanel: any Panel
    private let corners: [(corner: ScreenCorner, panel: any Panel)]
    private let radius = ScreenCorner.radius(on: ProcessInfo.processInfo.operatingSystemVersion)
    private let windowFrames: () -> [CGWindowID: CGRect]
    private let isOnScreen: (CGWindowID) -> Bool
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void
    private var shown = false
    private var secureInputIsActive = false
    private var tabArea = TabArea(display: .unknown)
    private var checkScheduled = false
    private var checkCount = 0
    private var observers: [NSObjectProtocol] = []

    var isEnabled: Bool {
        get { shown }
        set { newValue ? reveal() : dismiss(then: {}) }
    }

    /// `schedule` delays the check by 50ms: without the delay, the main queue runs a check between two window events of one
    /// workspace switch, and a switch between two workspaces that both cover the tab starts a restore and turns it back.
    init(
        workspaces: Workspaces,
        desktop: any Desktop,
        startWatchingWindows: (@escaping (WindowEvent) -> Void) -> Void,
        windowFrames: @escaping () -> [CGWindowID: CGRect],
        isOnScreen: @escaping (CGWindowID) -> Bool,
        startWatchingSecureInput: (@escaping (Bool) -> Void) -> Void,
        optionClicked: @escaping () -> Void = {},
        panel: (NSWindow.Level, SlidingView) -> any Panel = { OverlayPanel(level: $0, content: $1) },
        schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void = {
            DispatchQueue.main.asyncAfter(deadline: .now() + $0, execute: $1)
        },
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.windowFrames = windowFrames
        self.isOnScreen = isOnScreen
        self.schedule = schedule
        tab.optionClicked = optionClicked
        // One level below pop-up menus: above every window and the Dock, below a menu opened over the corner.
        let tabLevel = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)
        tabPanel = panel(tabLevel, tab)
        // Below the tab, which hides where a ring starts.
        cuePanel = panel(NSWindow.Level(rawValue: tabLevel.rawValue - 1), cue)
        // Same level as the Hammerspoon RoundedCorners spoon: above every window and menu.
        let maskLevel = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        let radius = radius
        corners = ScreenCorner.allCases.map { ($0, panel(maskLevel, Self.mask(of: $0, radius: radius))) }

        place(on: desktop.display)
        workspaces.startWatching { [weak self] event in self?.handle(event) }
        desktop.startWatching { [weak self] event in self?.handle(event) }
        startWatchingWindows { [weak self] _ in self?.scheduleCheck() }
        startWatchingSecureInput { [weak self] active in
            guard let self else { return }

            secureInputIsActive = active
            updateCue()
        }
        // Hiding an application reports no window event.
        observers = [NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification].map {
            notificationCenter.addObserver(forName: $0, object: nil, queue: .main) { [weak self] _ in self?.scheduleCheck() }
        }
    }

    var isRetracted: Bool { tab.isRetracted }
    var isCueShown: Bool { cue.isRevealed }
    var isCueRetracted: Bool { cue.isRetracted }

    /// `done` runs once the tab has slid out, or at once when the pager is not shown. A reveal during the slide runs it early.
    /// The masks slide out with the tab, for the same duration.
    func dismiss(then done: @escaping () -> Void) {
        guard shown else { return done() }

        shown = false
        for (_, panel) in corners {
            panel.conceal {}
        }
        tabPanel.conceal(then: done)
        updateCue()
    }

    private func handle(_ event: WorkspaceEvent) {
        switch event {
        case let .switched(workspace): tab.show(workspace: workspace)
        }
    }

    private func handle(_ event: DesktopEvent) {
        switch event {
        case let .displayChange(change):
            place(on: change.to)
            scheduleCheck()
        // The window list covers only the current Space.
        case .nativeSpaceChange: scheduleCheck()
        case .screenParametersChange: break
        }
    }

    /// The events of one change join the check the first of them scheduled.
    private func scheduleCheck() {
        guard !checkScheduled else { return }

        checkScheduled = true
        schedule(0.05) { [weak self] in
            guard let self else { return }

            checkScheduled = false
            guard shown else { return }

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

    /// The tab is not shown on a full screen Space, and the window list there holds that Space's windows only.
    private func check() {
        guard shown, isOnScreen(CGWindowID(tabPanel.windowNumber)) else { return }

        if tabArea.isOverlapped(by: windowFrames()) {
            tab.retract()
            cue.retract()
        } else {
            tab.restore()
            cue.restore()
        }
    }

    /// `display` is the one the desktop parks windows on.
    private func place(on display: Display) {
        tabArea = TabArea(display: display)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? display.fullFrame.height
        let screenFrame = display.fullFrame.flipped(primaryHeight: primaryHeight)

        tabPanel.setFrame(tabArea.frame.flipped(primaryHeight: primaryHeight), display: true)
        let cueFrame = tabArea.frame.bottomRight(size: CueView.size)
        cuePanel.setFrame(cueFrame.flipped(primaryHeight: primaryHeight), display: true)
        for (corner, panel) in corners {
            panel.setFrame(corner.frame(in: screenFrame, radius: radius), display: true)
        }
    }

    private func reveal() {
        guard !shown else { return }

        shown = true
        tabPanel.reveal()
        for (_, panel) in corners {
            panel.reveal()
        }
        scheduleCheck()
        updateCue()
    }

    /// The one rule for the cue: it shows while the pager is shown and an app holds secure event input.
    /// The guard covers a repeated report of the flag.
    private func updateCue() {
        let shows = shown && secureInputIsActive
        guard shows != cue.isRevealed else { return }

        if shows {
            cuePanel.reveal()
        } else {
            cuePanel.conceal {}
        }
    }

    private static func mask(of corner: ScreenCorner, radius: CGFloat) -> SlidingView {
        CATransaction.withoutActions {
            let mask = CAShapeLayer()
            mask.path = corner.mask(radius: radius)
            mask.fillColor = NSColor.black.cgColor
            return SlidingView(
                content: mask,
                size: CGSize(width: radius, height: radius),
                hiddenOffset: corner.hiddenOffset(radius: radius)
            )
        }
    }
}
