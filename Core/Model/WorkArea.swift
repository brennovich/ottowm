import CoreGraphics

/// The visible frame of a display and the spacing windows keep in it: where a frame change
/// sends a window, and the outcome to record for it.
struct WorkArea {
    private static let filledTolerance: CGFloat = 30

    let display: Display
    let spacing: CGFloat

    var hiddenEdge: HiddenEdge { HiddenEdge(display: display) }

    var filled: CGRect {
        display.visibleFrame.insetBy(dx: spacing, dy: spacing)
    }

    func frame(_ request: FrameRequest, from current: CGRect) -> (frame: CGRect, outcome: FrameOutcome) {
        let windowId = request.windowId

        switch request.change {
        case let .park(from: known):
            let onScreen = onScreen(known ?? current)
            return (hiddenEdge.frame(parking: onScreen), .parked(windowId, from: onScreen))
        case let .unpark(parkedFrom):
            return (onScreen(parkedFrom ?? current), .active(windowId))
        case let .move(direction):
            let step = Step(direction: direction, points: spacing)
            return (step.frame(moving: current, within: display.visibleFrame), .active(windowId))
        case let .resize(change):
            let resize = Resize(change: change, points: spacing)
            return (resize.frame(resizing: current, within: display.visibleFrame), .active(windowId))
        case .center:
            return (centered(current.size), .active(windowId))
        case let .maximize(restoring):
            return frame(filling: filled, from: current, restoring: restoring, of: windowId)
        case let .tile(direction, restoring):
            let half = Half(direction: direction).frame(within: filled, gap: spacing)
            return frame(filling: half, from: current, restoring: restoring, of: windowId)
        }
    }

    func onScreen(_ frame: CGRect) -> CGRect {
        hiddenEdge.holds(frame) ? centered(frame.size) : frame
    }

    /// Whether the window covers the target, within a tolerance.
    ///
    /// A window rarely settles at the size it was given: Terminal rounds its height to whole
    /// rows, tens of points at a large font size. The current frame of a window within the
    /// tolerance must not be recorded as the one to restore: restoring it would leave the
    /// window filled.
    func fills(_ current: CGRect, _ target: CGRect) -> Bool {
        abs(current.minX - target.minX) <= Self.filledTolerance
            && abs(current.minY - target.minY) <= Self.filledTolerance
            && abs(current.maxX - target.maxX) <= Self.filledTolerance
            && abs(current.maxY - target.maxY) <= Self.filledTolerance
    }

    /// A window already at the target is moved back to the frame it came from. Every
    /// target shares one record of that frame, so whether the window is filled is decided by
    /// its current frame, not by the presence of a record.
    private func frame(
        filling target: CGRect,
        from current: CGRect,
        restoring: CGRect?,
        of windowId: CGWindowID
    ) -> (frame: CGRect, outcome: FrameOutcome) {
        guard fills(current, target) else { return (target, .filled(windowId, from: current)) }
        return (restoring ?? current, .active(windowId))
    }

    private func centered(_ size: CGSize) -> CGRect {
        let bounds = display.visibleFrame

        return CGRect(
            x: bounds.minX + (bounds.width - size.width) / 2,
            y: bounds.minY + (bounds.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }
}
