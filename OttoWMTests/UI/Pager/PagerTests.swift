import XCTest

final class PagerTests: XCTestCase {
    func testDismissingAPagerThatIsNotShownIsDoneAtOnce() {
        let pager = Pager(
            workspaces: Workspaces(tabGroups: TabGroups(tabCount: { _ in 1 }, frame: { _ in nil })),
            desktop: StubDesktop()
        )
        var done = false

        pager.dismiss { done = true }

        XCTAssertTrue(done)
    }
}
