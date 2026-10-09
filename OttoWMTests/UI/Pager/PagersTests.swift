import XCTest

final class PagersTests: XCTestCase {
    private let overStandard = CGRect(x: 1700, y: 1000, width: 800, height: 600)
    private let overRight = CGRect(x: 3600, y: 800, width: 800, height: 600)
    private let away = CGRect(x: 0, y: 0, width: 800, height: 600)

    private let center = NotificationCenter()
    private var windowHandlers: [(WindowEvent) -> Void] = []
    private var secureInputHandler: ((Bool) -> Void)?
    private var listed: [CGWindowID: CGRect] = [:]
    private var listReads = 0
    private var scheduled: [(delay: TimeInterval, block: () -> Void)] = []

    private lazy var pagers = Pagers(
        startWatchingWindows: { self.windowHandlers.append($0) },
        windowFrames: {
            self.listReads += 1
            return self.listed
        },
        startWatchingSecureInput: { self.secureInputHandler = $0 },
        schedule: { self.scheduled.append(($0, $1)) },
        notificationCenter: center
    )

    override func setUp() {
        super.setUp()
        _ = pagers
    }

    private func makePager(on display: Display = .standard) -> Pager {
        let desktop = StubDesktop()
        desktop.display = display
        return Pager(
            workspaces: Workspaces(tabGroups: TabGroups(tabCount: { _ in 1 }, frame: { _ in nil })),
            desktop: desktop,
            isOnScreen: { _ in true },
            panel: StubPanel.init
        )
    }

    private func report(_ event: WindowEvent) {
        for handler in windowHandlers { handler(event) }
    }

    private func runScheduled() {
        let blocks = scheduled
        scheduled = []
        for (_, block) in blocks { block() }
    }

    private func enable() {
        pagers.isEnabled = true
        while !scheduled.isEmpty { runScheduled() }
    }

    func testEveryPagerFollowsIsEnabledIncludingOneAddedLater() {
        let first = makePager()
        let later = makePager()
        pagers.add(first, on: Display.standard.id)

        pagers.isEnabled = true
        pagers.add(later, on: Display.right.id)

        XCTAssertTrue(first.isEnabled)
        XCTAssertTrue(later.isEnabled)
    }

    func testEveryPagerGetsTheSecureInputFlagIncludingOneAddedLater() {
        let first = makePager()
        let later = makePager()
        pagers.add(first, on: Display.standard.id)
        pagers.isEnabled = true

        secureInputHandler?(true)
        pagers.add(later, on: Display.right.id)

        XCTAssertTrue(first.isCueShown)
        XCTAssertTrue(later.isCueShown)
    }

    func testDismissingRunsDoneOnceEveryPagerHasSlidOut() {
        pagers.add(makePager(), on: Display.standard.id)
        pagers.add(makePager(), on: Display.right.id)
        pagers.isEnabled = true
        let done = expectation(description: "every pager has slid out")

        pagers.dismiss { done.fulfill() }

        wait(for: [done], timeout: 1)
    }

    func testDismissingWithNoPagerIsDoneAtOnce() {
        var done = false

        pagers.dismiss { done = true }

        XCTAssertTrue(done)
    }

    func testOneCheckReadsTheWindowListOnceForEveryPager() {
        let standard = makePager(on: .standard)
        let right = makePager(on: .right)
        pagers.add(standard, on: Display.standard.id)
        pagers.add(right, on: Display.right.id)
        enable()
        let reads = listReads

        listed = [1: overStandard, 2: overRight]
        report(.reframed(nil))
        runScheduled()

        XCTAssertEqual(listReads, reads + 1)
        XCTAssertTrue(standard.isRetracted)
        XCTAssertTrue(right.isRetracted)
    }

    func testTheWindowListIsReadAgain130msAfterACheck() {
        let pager = makePager()
        pagers.add(pager, on: Display.standard.id)
        listed = [1: away]
        enable()
        report(.reframed(nil))
        runScheduled()
        XCTAssertFalse(pager.isRetracted)

        listed = [1: overStandard]
        XCTAssertEqual(scheduled.map(\.delay), [0.13])
        runScheduled()
        XCTAssertTrue(pager.isRetracted)
    }

    func testANewerCheckDropsThePendingRecheck() {
        pagers.add(makePager(), on: Display.standard.id)
        enable()
        report(.reframed(nil))
        runScheduled()
        let pendingRecheck = scheduled.removeFirst().block
        report(.reframed(nil))
        runScheduled()
        let reads = listReads

        pendingRecheck()

        XCTAssertEqual(listReads, reads)
    }

    func testEventsBeforeTheCheckRunsReadTheWindowListOnce() {
        pagers.add(makePager(), on: Display.standard.id)
        enable()
        let reads = listReads

        report(.reframed(nil))
        report(.reframed(nil))
        report(.destroyed(3))
        runScheduled()

        XCTAssertEqual(listReads, reads + 1)
    }

    func testHidingAnApplicationChecksAgain() {
        let pager = makePager()
        pagers.add(pager, on: Display.standard.id)
        listed = [1: overStandard]
        enable()

        listed = [:]
        center.post(name: NSWorkspace.didHideApplicationNotification, object: nil)
        runScheduled()

        XCTAssertFalse(pager.isRetracted)
    }

    func testWhileThePagerIsOffNoWindowListIsReadAndTurningItOnReadsItOnce() {
        pagers.add(makePager(), on: Display.standard.id)
        report(.reframed(nil))
        runScheduled()
        XCTAssertEqual(listReads, 0)

        pagers.isEnabled = true
        runScheduled()
        XCTAssertEqual(listReads, 1)
    }

    func testARemovedPagerIsDismissedAndNoLongerFollowsIsEnabled() {
        let pager = makePager()
        pagers.add(pager, on: Display.right.id)
        pagers.isEnabled = true

        pagers.remove(on: Display.right.id)
        pagers.isEnabled = true

        XCTAssertFalse(pager.isEnabled)
    }

    func testARemovedPagerIsReleasedOnceItHasSlidOut() {
        weak var removed: Pager?
        do {
            let pager = makePager()
            removed = pager
            pagers.add(pager, on: Display.right.id)
        }
        pagers.isEnabled = true

        pagers.remove(on: Display.right.id)

        XCTAssertNotNil(removed)
        let deadline = Date() + 1
        while removed != nil, Date() < deadline { RunLoop.current.run(until: Date() + 0.01) }
        XCTAssertNil(removed)
    }
}
