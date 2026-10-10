import AppKit

/// The tab in the parking corner with the current workspace, and the masks that round the screen corners.
/// The tab retracts while a window overlaps it, and the cue pulses under it while an app holds secure event input.
final class Pager {
    private let tab = PagerTabView()
    private let tabPanel: any Panel
    private let cue = CueView()
    private let cuePanel: any Panel
    private let corners: [(corner: ScreenCorner, panel: any Panel)]
    private let radius = ScreenCorner.radius(on: ProcessInfo.processInfo.operatingSystemVersion)
    private let isOnScreen: (CGWindowID) -> Bool
    private var shown = false
    private var secureInputIsActive = false
    private var tabArea = TabArea(display: .unknown)

    /// `Pagers` sets it to schedule the check of every Pager.
    var requestCheck: () -> Void = {}

    var isEnabled: Bool {
        get { shown }
        set { newValue ? reveal() : dismiss(then: {}) }
    }

    init(
        workspaces: Workspaces,
        desktop: any Desktop,
        isOnScreen: @escaping (CGWindowID) -> Bool,
        optionClicked: @escaping () -> Void = {},
        panel: (NSWindow.Level, SlidingView) -> any Panel = { OverlayPanel(level: $0, content: $1) }
    ) {
        self.isOnScreen = isOnScreen
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

    func secureInputChanged(_ active: Bool) {
        secureInputIsActive = active
        updateCue()
    }

    /// The tab is not shown on a full screen Space, and the window list there holds that Space's windows only.
    func check(against windowFrames: [CGWindowID: CGRect]) {
        guard shown, isOnScreen(CGWindowID(tabPanel.windowNumber)) else { return }

        if tabArea.isOverlapped(by: windowFrames) {
            tab.retract()
            cue.retract()
        } else {
            tab.restore()
            cue.restore()
        }
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
            requestCheck()
        // The window list covers only the current Space.
        case .nativeSpaceChange: requestCheck()
        case .screenParametersChange: break
        }
    }

    /// `display` is the one the desktop parks windows on.
    private func place(on display: Display) {
        tabArea = TabArea(display: display)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? display.fullFrame.height
        let screenFrame = display.fullFrame.flipped(primaryHeight: primaryHeight)

        tab.isMirrored = tabArea.isMirrored
        cue.isMirrored = tabArea.isMirrored
        tabPanel.setFrame(tabArea.frame.flipped(primaryHeight: primaryHeight), display: true)
        cuePanel.setFrame(tabArea.frame(of: CueView.size).flipped(primaryHeight: primaryHeight), display: true)
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
        requestCheck()
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
