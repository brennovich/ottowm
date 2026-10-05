import CoreGraphics
import Foundation

/// The Pager of each display.
final class Pagers {
    private let readWindowFrames: () -> [CGWindowID: CGRect]
    private let nextTurn: (@escaping () -> Void) -> Void
    private var pagers: [DisplayID: Pager] = [:]
    private var cachedWindowFrames: [CGWindowID: CGRect]?

    var isEnabled = false {
        didSet {
            for pager in pagers.values { pager.isEnabled = isEnabled }
        }
    }

    init(
        readWindowFrames: @escaping () -> [CGWindowID: CGRect] = {
            onScreenWindowFrames(level: Int(CGWindowLevelForKey(.normalWindow)))
        },
        nextTurn: @escaping (@escaping () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) }
    ) {
        self.readWindowFrames = readWindowFrames
        self.nextTurn = nextTurn
    }

    /// One change schedules the check of every Pager with the same delay, and the main queue runs those checks back to
    /// back, so the first read serves the others. A block queued on the main queue drops the read: it runs after the
    /// checks already due, in 199 of 200 runs of a scratch program; otherwise each check reads the list.
    func windowFrames() -> [CGWindowID: CGRect] {
        if let cachedWindowFrames { return cachedWindowFrames }

        let frames = readWindowFrames()
        cachedWindowFrames = frames
        nextTurn { [weak self] in self?.cachedWindowFrames = nil }
        return frames
    }

    func add(_ pager: Pager, on displayId: DisplayID) {
        pager.isEnabled = isEnabled
        pagers[displayId] = pager
    }

    /// The Pager is held until it has slid out: its panels are ordered out in a completion that holds them weakly.
    func remove(on displayId: DisplayID) {
        guard let pager = pagers.removeValue(forKey: displayId) else { return }

        pager.dismiss { _ = pager }
    }

    /// `done` runs once, after every Pager has slid out.
    func dismiss(then done: @escaping () -> Void) {
        var sliding = pagers.count
        guard sliding > 0 else { return done() }

        for pager in pagers.values {
            pager.dismiss {
                sliding -= 1
                if sliding == 0 { done() }
            }
        }
    }
}
