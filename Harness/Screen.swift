import AppKit

// Core/OffscreenParkingDesktop.swift insets the visible frame by this much before filling
// it, and leaves the same gap between the two halves of an axis.
let fillInset: CGFloat = 15

// Terminal fits its window to whole rows, 17pt at the default font, so a window handed a
// filled frame settles a row short of it. Core/Model/TabGroups.swift and
// OffscreenParkingDesktop.filledTolerance allow the same 30.
let refitTolerance: CGFloat = 30

// The frames below are worked out here rather than read from the app on purpose: the
// harness drives the shipped bundle without importing its code, so a change to
// Core/Model/Half.swift that the app and the run disagree about is a run that fails.

// What Core/ScreenGeometry.swift calls the visible frame, the display without the menu bar
// and the Dock, in the top left coordinates every frame read through the accessibility API
// is in. AppKit measures from the bottom left of the primary display.
func visibleFrame() -> CGRect {
    let screen = NSScreen.main ?? NSScreen.screens[0]
    let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
    let frame = screen.visibleFrame

    return CGRect(
        x: frame.origin.x,
        y: primaryHeight - frame.origin.y - frame.height,
        width: frame.width,
        height: frame.height
    )
}

// Where toggle-maximize takes a window.
func maximizedFrame() -> CGRect {
    visibleFrame().insetBy(dx: fillInset, dy: fillInset)
}

// Where `fill <direction>` takes a window. The two halves of an axis leave the gap between
// them, so a window taken to each in turn covers exactly the maximized frame.
func filledFrame(_ direction: Direction) -> CGRect {
    let bounds = maximizedFrame()
    let isVertical = direction == .north || direction == .south
    let width = isVertical ? bounds.width : (bounds.width - fillInset) / 2
    let height = isVertical ? (bounds.height - fillInset) / 2 : bounds.height

    return CGRect(
        x: direction == .east ? bounds.maxX - width : bounds.minX,
        y: direction == .south ? bounds.maxY - height : bounds.minY,
        width: width,
        height: height
    )
}

// Where center-window takes a window, which keeps the size it already has.
func centeredFrame(_ size: CGSize) -> CGRect {
    let bounds = visibleFrame()

    return CGRect(
        x: bounds.minX + (bounds.width - size.width) / 2,
        y: bounds.minY + (bounds.height - size.height) / 2,
        width: size.width,
        height: size.height
    )
}
