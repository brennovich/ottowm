import XCTest

final class AccessibilityPermissionTests: XCTestCase {
    private var trusted = false
    private var requests: [AccessibilityPermission.Request] = []
    private var responses: [AccessibilityPermission.Response] = []
    private var watchingWhenAsked: [Bool] = []
    private var openedSettings = false
    private var relaunches = 0
    private var quits = 0
    private var notifyChange: (() -> Void)?

    private func makePermission() -> AccessibilityPermission {
        AccessibilityPermission(
            isTrusted: { self.trusted },
            ask: { request in
                self.requests.append(request)
                self.watchingWhenAsked.append(self.notifyChange != nil)
                return self.responses.removeFirst()
            },
            openSettings: { self.openedSettings = true },
            watchForChange: { self.notifyChange = $0 },
            relaunch: { self.relaunches += 1 },
            quit: { self.quits += 1 }
        )
    }

    func testTheGateAsksUntilTheUserQuitsOrRestarts() {
        struct TestCase {
            let name: String
            let trusted: Bool
            let responses: [AccessibilityPermission.Response]
            let canStart: Bool
            let requests: [AccessibilityPermission.Request]
            let openedSettings: Bool
            let relaunches: Int
            let quits: Int
        }

        let testCases = [
            TestCase(
                name: "granted at launch",
                trusted: true,
                responses: [],
                canStart: true,
                requests: [],
                openedSettings: false,
                relaunches: 0,
                quits: 0
            ),
            TestCase(
                name: "quits at the first alert",
                trusted: false,
                responses: [.quit],
                canStart: false,
                requests: [.openSettings],
                openedSettings: false,
                relaunches: 0,
                quits: 1
            ),
            TestCase(
                name: "quits once settings are open",
                trusted: false,
                responses: [.confirm, .quit],
                canStart: false,
                requests: [.openSettings, .restart],
                openedSettings: true,
                relaunches: 0,
                quits: 1
            ),
            TestCase(
                name: "restarts on request",
                trusted: false,
                responses: [.confirm, .confirm],
                canStart: false,
                requests: [.openSettings, .restart],
                openedSettings: true,
                relaunches: 1,
                quits: 0
            ),
        ]

        for testCase in testCases {
            trusted = testCase.trusted
            responses = testCase.responses
            requests = []
            openedSettings = false
            relaunches = 0
            quits = 0

            XCTAssertEqual(makePermission().resolve(), testCase.canStart, testCase.name)
            XCTAssertEqual(requests, testCase.requests, testCase.name)
            XCTAssertEqual(openedSettings, testCase.openedSettings, testCase.name)
            XCTAssertEqual(relaunches, testCase.relaunches, testCase.name)
            XCTAssertEqual(quits, testCase.quits, testCase.name)
        }
    }

    func testAGrantArrivingWhileWaitingRelaunchesOnce() throws {
        responses = [.confirm, .quit]
        _ = makePermission().resolve()
        let changed = try XCTUnwrap(notifyChange)

        trusted = true
        changed()
        changed()

        XCTAssertEqual(relaunches, 1)
    }

    func testAChangeThatIsNotOurGrantKeepsWaiting() throws {
        responses = [.confirm, .quit]
        _ = makePermission().resolve()

        try XCTUnwrap(notifyChange)()

        XCTAssertEqual(relaunches, 0)
    }

    func testTheGrantIsWatchedForBeforeAnyAlertIsShown() {
        responses = [.confirm, .quit]

        _ = makePermission().resolve()

        XCTAssertEqual(watchingWhenAsked, [true, true])
    }
}
