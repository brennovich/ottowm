import AppKit
import SwiftUI

final class ScreenCorners {
    private let radius = ScreenCorner.radius(on: ProcessInfo.processInfo.operatingSystemVersion)
    private let panels: [(corner: ScreenCorner, panel: NSPanel)] = ScreenCorner.allCases.map { corner in
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // Same level as the Hammerspoon RoundedCorners spoon: above every window and menu.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: ScreenCornerView(corner: corner))
        return (corner, panel)
    }

    var isShown = false {
        didSet {
            guard isShown != oldValue else { return }

            for (_, panel) in panels {
                if isShown {
                    panel.orderFrontRegardless()
                } else {
                    panel.orderOut(nil)
                }
            }
        }
    }

    /// `screenFrame` is in AppKit coordinates.
    func place(in screenFrame: CGRect) {
        for (corner, panel) in panels {
            panel.setFrame(corner.frame(in: screenFrame, radius: radius), display: true)
        }
    }
}
