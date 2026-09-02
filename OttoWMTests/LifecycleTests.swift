import XCTest

final class LifecycleTests: XCTestCase {
    private var events: [String] = []
    private var terminated: (() -> Void)?
    private let center = NotificationCenter()

    private func makeLifecycle() -> Lifecycle {
        Lifecycle(
            stop: { self.events.append("stop") },
            resume: { self.events.append("resume") },
            screenLock: ScreenLock(notificationCenter: center, isLockedNow: { false }),
            exit: { self.events.append("exit \($0)") },
            launchNewInstance: { launched in
                self.events.append("launch")
                launched()
            },
            observeSIGTERM: { self.terminated = $0; return nil }
        )
    }

    func testQuitRestoresTheWindowsBeforeItExits() {
        makeLifecycle().quit()

        XCTAssertEqual(events, ["stop", "exit 0"])
    }

    func testSIGTERMRestoresTheWindowsBeforeItExits() throws {
        let lifecycle = makeLifecycle()

        lifecycle.startWatchingSIGTERM()
        XCTAssertEqual(events, [])

        try XCTUnwrap(terminated)()

        XCTAssertEqual(events, ["stop", "exit 0"])
    }

    func testRelaunchRestoresTheWindowsBeforeTheNewInstanceReplacesIt() {
        makeLifecycle().relaunch()

        XCTAssertEqual(events, ["stop", "launch", "exit 0"])
    }

    func testUnlockingTheScreenResumes() {
        let lifecycle = makeLifecycle()

        lifecycle.startWatchingScreenLock()
        center.postScreenLocked()
        XCTAssertEqual(events, [])

        center.postScreenUnlocked()

        XCTAssertEqual(events, ["resume"])
    }

    func testTheScreenLockStateIsReported() {
        let lifecycle = makeLifecycle()
        lifecycle.startWatchingScreenLock()

        XCTAssertFalse(lifecycle.screenIsLocked)

        center.postScreenLocked()

        XCTAssertTrue(lifecycle.screenIsLocked)

        center.postScreenUnlocked()

        XCTAssertFalse(lifecycle.screenIsLocked)
    }
}
