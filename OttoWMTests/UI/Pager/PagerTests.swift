import XCTest

final class PagerTests: XCTestCase {
    private let over = CGRect(x: 1700, y: 1000, width: 800, height: 600)
    private let away = CGRect(x: 0, y: 0, width: 800, height: 600)

    private let desktop = StubDesktop()
    private let center = NotificationCenter()
    private var windowHandlers: [(WindowEvent) -> Void] = []
    private var listed: [CGWindowID: CGRect] = [:]
    private var listReads = 0
    private var tabOnScreen = true
    private var scheduled: [(delay: TimeInterval, block: () -> Void)] = []
    private var secureInputHandler: ((Bool) -> Void)?

    private lazy var pager = Pager(
        workspaces: Workspaces(tabGroups: TabGroups(tabCount: { _ in 1 }, frame: { _ in nil })),
        desktop: desktop,
        startWatchingWindows: { self.windowHandlers.append($0) },
        windowFrames: {
            self.listReads += 1
            return self.listed
        },
        isOnScreen: { _ in self.tabOnScreen },
        startWatchingSecureInput: { self.secureInputHandler = $0 },
        panel: StubPanel.init,
        schedule: { self.scheduled.append(($0, $1)) },
        notificationCenter: center
    )

    override func setUp() {
        super.setUp()
        _ = pager
    }

    private func report(_ event: WindowEvent) {
        for handler in windowHandlers { handler(event) }
    }

    private func report(secureInput active: Bool) {
        secureInputHandler?(active)
    }

    private func runScheduled() {
        let blocks = scheduled
        scheduled = []
        for (_, block) in blocks { block() }
    }

    private func enable() {
        pager.isEnabled = true
        while !scheduled.isEmpty { runScheduled() }
    }

    func testDismissingAPagerThatIsNotShownIsDoneAtOnce() {
        var done = false

        pager.dismiss { done = true }

        XCTAssertTrue(done)
    }

    func testAWindowOverTheTabRetractsItAndMovingAwayRestoresIt() {
        listed = [1: away]
        enable()

        listed = [1: over]
        report(.reframed)
        runScheduled()
        XCTAssertTrue(pager.isRetracted)
        XCTAssertTrue(pager.isCueRetracted)

        listed = [1: away]
        report(.reframed)
        runScheduled()
        XCTAssertFalse(pager.isRetracted)
        XCTAssertFalse(pager.isCueRetracted)
    }

    func testTheCueShowsWhileSecureInputIsSet() {
        enable()

        report(secureInput: true)
        XCTAssertTrue(pager.isCueShown)

        report(secureInput: false)
        XCTAssertFalse(pager.isCueShown)
    }

    func testTheCueShowsOnlyOnceThePagerIsShown() {
        report(secureInput: true)
        XCTAssertFalse(pager.isCueShown)

        enable()

        XCTAssertTrue(pager.isCueShown)
    }

    func testTurningThePagerOffTakesTheCueWithIt() {
        enable()
        report(secureInput: true)
        let done = expectation(description: "the pager has slid out")

        pager.dismiss { done.fulfill() }

        XCTAssertFalse(pager.isCueShown)
        wait(for: [done], timeout: 1)
    }

    func testWhileTheTabIsNotOnScreenTheCheckLeavesItAsItIs() {
        listed = [1: over]
        tabOnScreen = false

        enable()

        XCTAssertFalse(pager.isRetracted)
    }

    func testTheWindowListIsReadAgain130msAfterACheck() {
        listed = [1: away]
        enable()
        report(.reframed)
        runScheduled()
        XCTAssertFalse(pager.isRetracted)

        listed = [1: over]
        XCTAssertEqual(scheduled.map(\.delay), [0.13])
        runScheduled()
        XCTAssertTrue(pager.isRetracted)
    }

    func testANewerCheckDropsThePendingRecheck() {
        enable()
        report(.reframed)
        runScheduled()
        let pendingRecheck = scheduled.removeFirst().block
        report(.reframed)
        runScheduled()
        let reads = listReads

        pendingRecheck()

        XCTAssertEqual(listReads, reads)
    }

    func testEventsBeforeTheCheckRunsReadTheWindowListOnce() {
        enable()
        let reads = listReads

        report(.reframed)
        report(.reframed)
        report(.destroyed(3))
        runScheduled()

        XCTAssertEqual(listReads, reads + 1)
    }

    func testADisplayChangeChecksAgainstTheNewDisplay() {
        listed = [1: CGRect(x: 2000, y: 1000, width: 800, height: 600)]
        enable()

        desktop.report(.displayChange(DisplayChange(from: .standard, to: .external)))
        runScheduled()

        XCTAssertTrue(pager.isRetracted)
    }

    func testANativeSpaceChangeChecksAgain() {
        enable()

        listed = [1: over]
        desktop.report(.nativeSpaceChange)
        runScheduled()

        XCTAssertTrue(pager.isRetracted)
    }

    func testHidingAnApplicationChecksAgain() {
        listed = [1: over]
        enable()

        listed = [:]
        center.post(name: NSWorkspace.didHideApplicationNotification, object: nil)
        runScheduled()

        XCTAssertFalse(pager.isRetracted)
    }

    func testWhileThePagerIsOffNoWindowListIsReadAndTurningItOnReadsItOnce() {
        report(.reframed)
        runScheduled()
        XCTAssertEqual(listReads, 0)

        pager.isEnabled = true
        runScheduled()
        XCTAssertEqual(listReads, 1)
    }
}
