import XCTest

final class AccessibilityPermissionTests: XCTestCase {
    private var trusted = false
    private var requests: [AccessibilityPermission.Request] = []
    private var responses: [AccessibilityPermission.Response] = []
    private var watchingWhenAsked: [Bool] = []
    private var openedSettings = false
    private var relaunches = 0
    private var releases = 0
    private var restarts = 0
    private var notifyChange: (() -> Void)?
    private var whileAsking: (() -> Void)?

    private func makePermission() -> AccessibilityPermission {
        AccessibilityPermission(
            isTrusted: { self.trusted },
            ask: { request in
                self.requests.append(request)
                self.watchingWhenAsked.append(self.notifyChange != nil)
                self.whileAsking?()
                return self.responses.removeFirst()
            },
            openSettings: { self.openedSettings = true },
            observeTrustChanges: { self.notifyChange = $0 },
            relaunch: { self.relaunches += 1 }
        )
    }

    func testTheGateAsksUntilTheUserQuitsOrRestarts() {
        struct TestCase {
            let name: String
            let trusted: Bool
            let responses: [AccessibilityPermission.Response]
            let outcome: AccessibilityPermission.Outcome
            let requests: [AccessibilityPermission.Request]
            let openedSettings: Bool
            let relaunches: Int
        }

        let testCases = [
            TestCase(
                name: "granted at launch",
                trusted: true,
                responses: [],
                outcome: .granted,
                requests: [],
                openedSettings: false,
                relaunches: 0
            ),
            TestCase(
                name: "quits at the first alert",
                trusted: false,
                responses: [.quit],
                outcome: .quit,
                requests: [.openSettings],
                openedSettings: false,
                relaunches: 0
            ),
            TestCase(
                name: "quits once settings are open",
                trusted: false,
                responses: [.confirm, .quit],
                outcome: .quit,
                requests: [.openSettings, .restart],
                openedSettings: true,
                relaunches: 0
            ),
            TestCase(
                name: "restarts on request",
                trusted: false,
                responses: [.confirm, .confirm],
                outcome: .relaunching,
                requests: [.openSettings, .restart],
                openedSettings: true,
                relaunches: 1
            ),
        ]

        for testCase in testCases {
            trusted = testCase.trusted
            responses = testCase.responses
            requests = []
            openedSettings = false
            relaunches = 0

            XCTAssertEqual(makePermission().request(), testCase.outcome, testCase.name)
            XCTAssertEqual(requests, testCase.requests, testCase.name)
            XCTAssertEqual(openedSettings, testCase.openedSettings, testCase.name)
            XCTAssertEqual(relaunches, testCase.relaunches, testCase.name)
        }
    }

    func testAGrantArrivingWhileWaitingRelaunchesOnce() throws {
        responses = [.confirm, .quit]
        _ = makePermission().request()
        let changed = try XCTUnwrap(notifyChange)

        trusted = true
        changed()
        changed()

        XCTAssertEqual(relaunches, 1)
    }

    func testAGrantArrivingWhileAnAlertIsUpRelaunchesEvenIfTheUserQuits() {
        responses = [.quit]
        whileAsking = {
            self.trusted = true
            self.notifyChange?()
        }

        XCTAssertEqual(makePermission().request(), .relaunching)
        XCTAssertEqual(relaunches, 1)
    }

    func testAChangeThatIsNotOurGrantKeepsWaiting() throws {
        responses = [.confirm, .quit]
        _ = makePermission().request()

        try XCTUnwrap(notifyChange)()

        XCTAssertEqual(relaunches, 0)
    }

    func testTheGrantIsWatchedForBeforeAnyAlertIsShown() {
        responses = [.confirm, .quit]

        _ = makePermission().request()

        XCTAssertEqual(watchingWhenAsked, [true, true])
    }

    func testARevocationWhileRunningReleasesTheTapOnce() throws {
        trusted = true
        startWatchingTrust()
        let changed = try XCTUnwrap(notifyChange)

        trusted = false
        changed()
        changed()

        XCTAssertEqual(releases, 1)
        XCTAssertEqual(restarts, 0)
    }

    func testAChangeThatLeavesTheTrustInPlaceReleasesNothing() throws {
        trusted = true
        startWatchingTrust()

        try XCTUnwrap(notifyChange)()

        XCTAssertEqual(releases, 0)
        XCTAssertEqual(restarts, 0)
    }

    // The workspace assignments and the frames of the parked windows only live in
    // memory, and a revocation leaves them untouched: relaunching would collapse
    // every window into workspace 1 and lose the frame each parked one is owed.
    func testTrustComingBackAfterARevocationRestartsInPlace() throws {
        trusted = true
        startWatchingTrust()
        let changed = try XCTUnwrap(notifyChange)

        trusted = false
        changed()
        trusted = true
        changed()
        changed()

        XCTAssertEqual(releases, 1)
        XCTAssertEqual(restarts, 1)
        XCTAssertEqual(relaunches, 0)
    }

    private func startWatchingTrust() {
        makePermission().startWatchingTrust(
            lost: { self.releases += 1 },
            regained: { self.restarts += 1 }
        )
    }
}
