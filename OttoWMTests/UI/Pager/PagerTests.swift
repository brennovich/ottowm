import XCTest

final class PagerTests: XCTestCase {
    private let over = CGRect(x: 1700, y: 1000, width: 800, height: 600)
    private let away = CGRect(x: 0, y: 0, width: 800, height: 600)

    private let desktop = StubDesktop()
    private var tabOnScreen = true
    private var requestedChecks = 0
    private var views: [SlidingView] = []

    private lazy var pager = Pager(
        workspaces: Workspaces(tabGroups: TabGroups(tabCount: { _ in 1 }, frame: { _ in nil })),
        desktop: desktop,
        isOnScreen: { _ in self.tabOnScreen },
        panel: { level, view in
            self.views.append(view)
            return StubPanel(level: level, content: view)
        }
    )

    override func setUp() {
        super.setUp()
        pager.requestCheck = { self.requestedChecks += 1 }
    }

    func testDismissingAPagerThatIsNotShownIsDoneAtOnce() {
        var done = false

        pager.dismiss { done = true }

        XCTAssertTrue(done)
    }

    func testAWindowOverTheTabRetractsItAndMovingAwayRestoresIt() {
        pager.isEnabled = true

        pager.check(against: [1: over])
        XCTAssertTrue(pager.isRetracted)
        XCTAssertTrue(pager.isCueRetracted)

        pager.check(against: [1: away])
        XCTAssertFalse(pager.isRetracted)
        XCTAssertFalse(pager.isCueRetracted)
    }

    func testTheCueShowsWhileSecureInputIsSet() {
        pager.isEnabled = true

        pager.secureInputChanged(true)
        XCTAssertTrue(pager.isCueShown)

        pager.secureInputChanged(false)
        XCTAssertFalse(pager.isCueShown)
    }

    func testTheCueShowsOnlyOnceThePagerIsShown() {
        pager.secureInputChanged(true)
        XCTAssertFalse(pager.isCueShown)

        pager.isEnabled = true

        XCTAssertTrue(pager.isCueShown)
    }

    func testTurningThePagerOffTakesTheCueWithIt() {
        pager.isEnabled = true
        pager.secureInputChanged(true)
        let done = expectation(description: "the pager has slid out")

        pager.dismiss { done.fulfill() }

        XCTAssertFalse(pager.isCueShown)
        wait(for: [done], timeout: 1)
    }

    func testWhileTheTabIsNotOnScreenTheCheckLeavesItAsItIs() {
        tabOnScreen = false
        pager.isEnabled = true

        pager.check(against: [1: over])

        XCTAssertFalse(pager.isRetracted)
    }

    func testADisplayChangeChecksAgainstTheNewDisplay() {
        desktop.report(.displayChange(DisplayChange(from: .standard, to: .external)))
        XCTAssertEqual(requestedChecks, 1)

        pager.isEnabled = true
        pager.check(against: [1: CGRect(x: 2000, y: 1000, width: 800, height: 600)])
        XCTAssertTrue(pager.isRetracted)
    }

    func testTheTabAndTheCueAreMirroredOnADisplayParkingInTheBottomLeft() {
        _ = pager
        let display = Display.standard.parking(at: .bottomLeft)

        desktop.report(.displayChange(DisplayChange(from: .standard, to: display)))

        XCTAssertTrue(views.contains { $0 is PagerTabView && $0.isMirrored })
        XCTAssertTrue(views.contains { $0 is CueView && $0.isMirrored })
    }

    func testANativeSpaceChangeChecksAgain() {
        desktop.report(.nativeSpaceChange)

        XCTAssertEqual(requestedChecks, 1)
    }
}
