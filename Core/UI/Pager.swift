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
    private let corners = ScreenCorners()

    var isShown = false {
        didSet {
            guard isShown != oldValue else { return }

            if isShown {
                panel.orderFrontRegardless()
            } else {
                panel.orderOut(nil)
            }
            corners.isShown = isShown
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
    }

    func show(workspace: Int) {
        tab.rootView = PagerView(workspace: workspace)
    }

    /// `display` is the one the desktop parks windows on.
    func place(on display: Display) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? display.fullFrame.height
        let screenFrame = display.fullFrame.flippedToBottomLeft(primaryHeight: primaryHeight)

        panel.setFrame(PagerTab.frame(in: screenFrame), display: true)
        corners.place(in: screenFrame)
    }
}
