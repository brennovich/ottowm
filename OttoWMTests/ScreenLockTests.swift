import Foundation
import XCTest

final class ScreenLockTests: XCTestCase {
    private let center = NotificationCenter()
    private lazy var screenLock = ScreenLock(notificationCenter: center, isLockedNow: { false })

    func testAScreenNobodyLockedIsUnlocked() {
        XCTAssertFalse(screenLock.isLocked)
    }

    func testAScreenAlreadyLockedAtLaunchIsLocked() {
        XCTAssertTrue(ScreenLock(notificationCenter: center, isLockedNow: { true }).isLocked)
    }

    func testLockingAndUnlockingFollowTheSystemNotifications() {
        var unlocks = 0
        screenLock.startWatching { unlocks += 1 }

        center.postScreenLocked()

        XCTAssertTrue(screenLock.isLocked)
        XCTAssertEqual(unlocks, 0)

        center.postScreenUnlocked()

        XCTAssertFalse(screenLock.isLocked)
        XCTAssertEqual(unlocks, 1)
    }

    func testNotificationsBeforeWatchingAreIgnored() {
        center.postScreenLocked()

        XCTAssertFalse(screenLock.isLocked)
    }

    func testWatchingTwiceLeavesOneSubscription() {
        var unlocks = 0
        screenLock.startWatching { unlocks += 1 }
        screenLock.startWatching { unlocks += 1 }

        center.postScreenUnlocked()

        XCTAssertEqual(unlocks, 1)
    }
}

extension NotificationCenter {
    func postScreenLocked() {
        post(name: Notification.Name("com.apple.screenIsLocked"), object: nil)
    }

    func postScreenUnlocked() {
        post(name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
    }
}
