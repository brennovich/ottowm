import AppKit

extension NSWindow {
    static func offscreen(hosting view: NSView = NSView()) -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 60, height: 60),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        view.wantsLayer = true
        window.contentView = view
        return window
    }

    static func offscreen(hosting layer: CALayer) -> NSWindow {
        let window = offscreen()
        window.contentView?.layer?.addSublayer(layer)
        return window
    }
}
