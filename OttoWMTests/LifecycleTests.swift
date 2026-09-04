import XCTest

final class LifecycleTests: XCTestCase {
    private var events: [String] = []
    private var terminated: (() -> Void)?
    private let center = NotificationCenter()
    private var reloadError: ConfigError?
    private var asked: [ConfigError] = []
    private var response: ConfigAlert.Response = .dismiss
    private var whileAsking: (() -> Void)?

    private func makeLifecycle() -> Lifecycle {
        Lifecycle(
            stop: { self.events.append("stop") },
            resume: { self.events.append("resume") },
            reloadBindings: {
                self.events.append("reload")
                return self.reloadError
            },
            ask: { error in
                self.asked.append(error)
                let reentrant = self.whileAsking
                self.whileAsking = nil
                reentrant?()
                return self.response
            },
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

    func testAConfigThatParsesIsTakenWithoutAskingAnything() {
        makeLifecycle().reload()

        XCTAssertEqual(events, ["reload"])
        XCTAssertEqual(asked, [])
    }

    func testAConfigThatDoesNotParseIsShownAndLeavesTheBindingsAndTheProcessUp() {
        let error = ConfigError(line: 2, reason: .unknownAction("relaunch"))
        reloadError = error

        makeLifecycle().reload()

        XCTAssertEqual(asked, [error])
        XCTAssertEqual(events, ["reload"])
    }

    func testAReloadArrivingWhileTheAlertIsUpIsDropped() {
        reloadError = ConfigError(line: 2, reason: .unknownAction("relaunch"))
        let lifecycle = makeLifecycle()
        whileAsking = { lifecycle.reload() }

        lifecycle.reload()

        XCTAssertEqual(asked.count, 1)
        XCTAssertEqual(events, ["reload"])
    }

    func testRestartingOverAConfigErrorRelaunches() {
        reloadError = ConfigError(line: 2, reason: .unknownAction("relaunch"))
        response = .restart

        makeLifecycle().reload()

        XCTAssertEqual(events, ["reload", "stop", "launch", "exit 0"])
    }

    func testLockingTheScreenIsReportedAndUnlockingItResumes() {
        let lifecycle = makeLifecycle()

        lifecycle.startWatchingScreenLock()
        center.postScreenLocked()
        XCTAssertEqual(events, [])
        XCTAssertTrue(lifecycle.screenIsLocked)

        center.postScreenUnlocked()

        XCTAssertEqual(events, ["resume"])
        XCTAssertFalse(lifecycle.screenIsLocked)
    }
}
