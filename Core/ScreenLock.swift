import CoreGraphics
import Foundation

// Posted by the login window as it covers and uncovers the session. Undeclared by any
// header, and distributed rather than per-process: every session gets them.
private let screenLockedNotification = "com.apple.screenIsLocked"
private let screenUnlockedNotification = "com.apple.screenIsUnlocked"

// Whether the login window is covering the session.
//
// Behind it every accessibility attribute reads blank and window ids come back nil, so
// each application looks like it closed all of its windows at once. Taken at face value
// that unmanages them, and with them goes the frame every parked window is owed: one
// that was at the hidden edge when the screen locked would stay in the corner for good.
final class ScreenLock {
    private let notificationCenter: NotificationCenter

    private(set) var isLocked: Bool
    private var observers: [any NSObjectProtocol] = []

    // The notifications only say what changes from now on, and OttoWM can be launched
    // behind a lock screen: relaunching itself after an accessibility grant is enough.
    init(
        notificationCenter: NotificationCenter = DistributedNotificationCenter.default(),
        isLockedNow: () -> Bool = { (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Int == 1 }
    ) {
        self.notificationCenter = notificationCenter
        isLocked = isLockedNow()
    }

    // The unlock callback is where anything skipped during the lock is caught up on:
    // what really changed while the screen was covered is only knowable now.
    func startWatching(unlocked: @escaping () -> Void) {
        stopWatching()
        observers = [
            observe(screenLockedNotification) { [weak self] in
                self?.isLocked = true
                Log.app.info("screen locked, window events are on hold")
            },
            observe(screenUnlockedNotification) { [weak self] in
                self?.isLocked = false
                Log.app.info("screen unlocked")
                unlocked()
            },
        ]
    }

    private func observe(_ name: String, _ handler: @escaping () -> Void) -> any NSObjectProtocol {
        notificationCenter.addObserver(forName: Notification.Name(name), object: nil, queue: nil) { _ in
            handler()
        }
    }

    private func stopWatching() {
        for observer in observers {
            notificationCenter.removeObserver(observer)
        }
        observers = []
    }

    deinit {
        stopWatching()
    }
}
