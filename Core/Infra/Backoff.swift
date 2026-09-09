import Foundation

/// Repeats an attempt with the delay doubled each time, from `first` up to `last`.
struct Backoff {
    static let onMainQueue: (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    let schedule: (TimeInterval, @escaping () -> Void) -> Void
    let first: TimeInterval
    let last: TimeInterval

    /// - Parameter attempt: returns `true` once there is nothing left to retry.
    func run(_ attempt: @escaping () -> Bool) {
        retry(after: first, attempt)
    }

    private func retry(after delay: TimeInterval, _ attempt: @escaping () -> Bool) {
        guard delay <= last else { return }

        schedule(delay) {
            if !attempt() { retry(after: delay * 2, attempt) }
        }
    }
}
