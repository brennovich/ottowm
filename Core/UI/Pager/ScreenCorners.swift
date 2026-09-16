import AppKit

final class ScreenCorners {
    private let radius = ScreenCorner.radius(on: ProcessInfo.processInfo.operatingSystemVersion)
    private lazy var panels: [(corner: ScreenCorner, panel: NSPanel, view: ScreenCornerView)] = ScreenCorner.allCases.map { corner in
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // Same level as the Hammerspoon RoundedCorners spoon: above every window and menu.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.stationary, .ignoresCycle]
        let view = ScreenCornerView(corner: corner, radius: radius)
        panel.contentView = view
        return (corner, panel, view)
    }

    var isShown = false {
        didSet {
            guard isShown != oldValue else { return }

            if isShown {
                reveal()
            } else {
                conceal()
            }
        }
    }

    /// `screenFrame` is in AppKit coordinates.
    func place(in screenFrame: CGRect) {
        for (corner, panel, _) in panels {
            panel.setFrame(corner.frame(in: screenFrame, radius: radius), display: true)
        }
    }

    private func reveal() {
        for (_, panel, view) in panels {
            panel.orderFrontRegardless()
            view.reveal()
        }
    }

    private func conceal() {
        for (_, panel, view) in panels {
            view.conceal { [weak self] in
                guard self?.isShown == false else { return }
                panel.orderOut(nil)
            }
        }
    }
}
