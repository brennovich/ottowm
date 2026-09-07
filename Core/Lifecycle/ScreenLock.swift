import CoreGraphics
import Foundation

final class ScreenLock {
    private let notificationCenter: NotificationCenter

    private(set) var isLocked: Bool
    private var observers: [any NSObjectProtocol] = []

    init(
        notificationCenter: NotificationCenter = DistributedNotificationCenter.default(),
        isLockedNow: () -> Bool = { (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Int == 1 }
    ) {
        self.notificationCenter = notificationCenter
        isLocked = isLockedNow()
    }

    func startWatching(unlocked: @escaping () -> Void) {
        stopWatching()

        observers = [
            notificationCenter.addObserver(
                forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: nil) { [weak self] _ in
                    self?.isLocked = true
                    Log.app.info("screen locked, window events are on hold")
                },
            notificationCenter.addObserver(
                forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: nil) { [weak self] _ in
                    self?.isLocked = false
                    Log.app.info("screen unlocked")
                    unlocked()
                },
        ]
    }

    private func stopWatching() {
        observers.forEach(notificationCenter.removeObserver)
        observers = []
    }

    deinit {
        stopWatching()
    }
}
