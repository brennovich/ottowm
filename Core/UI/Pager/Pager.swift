import AppKit

final class Pager {
    static let transitionDuration: TimeInterval = 0.3
    static let workspaceChangeDuration: TimeInterval = 0.3

    private let panel = NSPanel(
        contentRect: .zero,
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    private let tab = PagerTabView()
    private let corners = ScreenCorners()
    private var shown = false

    var isEnabled: Bool {
        get { shown }
        set { newValue ? reveal() : dismiss(then: {}) }
    }

    init(workspaces: Workspaces, desktop: any Desktop) {
        // One level below pop-up menus: above every window and the Dock, below a menu opened over the corner.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        // A click on the corner reaches the parked window under the tab.
        panel.ignoresMouseEvents = true
        // A panel hides when its application deactivates, and OttoWM is inactive except while an alert shows.
        panel.hidesOnDeactivate = false
        // Without `.canJoinAllSpaces` the panel stays on the native Space it is shown on.
        panel.collectionBehavior = [.stationary, .ignoresCycle]
        panel.contentView = tab

        place(on: desktop.display)
        workspaces.startWatching { [weak self] event in self?.handle(event) }
        desktop.startWatching { [weak self] event in self?.handle(event) }
    }

    /// `done` runs once the tab has slid out, or at once when the pager is not shown. A reveal during the slide runs it early.
    func dismiss(then done: @escaping () -> Void) {
        guard shown else { return done() }

        shown = false
        corners.isShown = false
        tab.conceal { [weak self] in
            if let self, !self.shown {
                self.panel.orderOut(nil)
            }
            done()
        }
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
        let screenFrame = display.fullFrame.flippedToBottomLeft(primaryHeight: primaryHeight)

        panel.setFrame(PagerTab.frame(in: screenFrame), display: true)
        corners.place(in: screenFrame)
    }

    private func reveal() {
        guard !shown else { return }

        shown = true
        panel.orderFrontRegardless()
        tab.reveal()
        corners.isShown = true
    }
}
