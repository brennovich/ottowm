import AppKit
import SwiftUI

final class Pager {
    private let panel = NSPanel(
        contentRect: .zero,
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    private let tab = NSHostingView(rootView: PagerView(workspace: 1))

    var isShown = false {
        didSet {
            guard isShown != oldValue else { return }

            if isShown {
                panel.orderFrontRegardless()
            } else {
                panel.orderOut(nil)
            }
        }
    }

    init() {
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

        place()
        _ = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.place() }
    }

    func show(workspace: Int) {
        tab.rootView = PagerView(workspace: workspace)
    }

    /// The same screen `MainScreen` reports to the desktop.
    private func place() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        panel.setFrame(PagerTab.frame(in: screen.frame), display: true)
    }
}
