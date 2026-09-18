import AppKit

/// The tab in the bottom right corner with the current workspace, and the masks that round the other three screen corners.
final class Pager {
    private let tab = PagerTabView()
    private let tabPanel: OverlayPanel
    private let corners: [(corner: ScreenCorner, panel: OverlayPanel)]
    private let radius = ScreenCorner.radius(on: ProcessInfo.processInfo.operatingSystemVersion)
    private var shown = false

    var isEnabled: Bool {
        get { shown }
        set { newValue ? reveal() : dismiss(then: {}) }
    }

    init(workspaces: Workspaces, desktop: any Desktop) {
        // One level below pop-up menus: above every window and the Dock, below a menu opened over the corner.
        tabPanel = OverlayPanel(level: NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1), content: tab)
        // Same level as the Hammerspoon RoundedCorners spoon: above every window and menu.
        let maskLevel = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        let radius = radius
        corners = ScreenCorner.allCases.map { ($0, OverlayPanel(level: maskLevel, content: Self.mask(of: $0, radius: radius))) }

        place(on: desktop.display)
        workspaces.startWatching { [weak self] event in self?.handle(event) }
        desktop.startWatching { [weak self] event in self?.handle(event) }
    }

    /// `done` runs once the tab has slid out, or at once when the pager is not shown. A reveal during the slide runs it early.
    /// The masks slide out with the tab, for the same duration.
    func dismiss(then done: @escaping () -> Void) {
        guard shown else { return done() }

        shown = false
        for (_, panel) in corners {
            panel.conceal {}
        }
        tabPanel.conceal(then: done)
    }

    private func handle(_ event: WorkspaceEvent) {
        switch event {
        case let .switched(workspace): tab.show(workspace: workspace)
        }
    }

    private func handle(_ event: DesktopEvent) {
        switch event {
        case let .displayChange(change): place(on: change.to)
        case .nativeSpaceChange, .screenParametersChange: break
        }
    }

    /// `display` is the one the desktop parks windows on.
    private func place(on display: Display) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? display.fullFrame.height
        let screenFrame = display.fullFrame.flipped(primaryHeight: primaryHeight)

        tabPanel.setFrame(PagerTabView.frame(in: screenFrame), display: true)
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
