import XCTest

final class PagersTests: XCTestCase {
    private let pagers = Pagers()

    private func makePager() -> Pager {
        Pager(
            workspaces: Workspaces(tabGroups: TabGroups(tabCount: { _ in 1 }, frame: { _ in nil })),
            desktop: StubDesktop(),
            startWatchingWindows: { _ in {} },
            windowFrames: { [:] },
            isOnScreen: { _ in true },
            startWatchingSecureInput: { _ in {} },
            panel: StubPanel.init,
            schedule: { _, _ in },
            notificationCenter: NotificationCenter()
        )
    }

    func testEveryPagerFollowsIsEnabledIncludingOneAddedLater() {
        let first = makePager()
        let later = makePager()
        pagers.add(first, on: Display.standard.id)

        pagers.isEnabled = true
        pagers.add(later, on: Display.airPlay.id)

        XCTAssertTrue(first.isEnabled)
        XCTAssertTrue(later.isEnabled)
    }

    func testDismissingRunsDoneOnceEveryPagerHasSlidOut() {
        pagers.add(makePager(), on: Display.standard.id)
        pagers.add(makePager(), on: Display.airPlay.id)
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

    func testTheWindowListIsReadOnceUntilTheMainQueueRunsItsNextBlock() {
        var reads = 0
        var nextBlocks: [() -> Void] = []
        let pagers = Pagers(
            readWindowFrames: {
                reads += 1
                return [CGWindowID(reads): .zero]
            },
            nextTurn: { nextBlocks.append($0) }
        )
        _ = pagers.windowFrames()

        XCTAssertEqual(pagers.windowFrames(), [1: .zero])

        for block in nextBlocks { block() }

        XCTAssertEqual(pagers.windowFrames(), [2: .zero])
    }

    func testARemovedPagerIsDismissedAndNoLongerFollowsIsEnabled() {
        let pager = makePager()
        pagers.add(pager, on: Display.airPlay.id)
        pagers.isEnabled = true

        pagers.remove(on: Display.airPlay.id)
        pagers.isEnabled = true

        XCTAssertFalse(pager.isEnabled)
    }

    func testARemovedPagerIsReleasedOnceItHasSlidOut() {
        weak var removed: Pager?
        do {
            let pager = makePager()
            removed = pager
            pagers.add(pager, on: Display.airPlay.id)
        }
        pagers.isEnabled = true

        pagers.remove(on: Display.airPlay.id)

        XCTAssertNotNil(removed)
        let deadline = Date() + 1
        while removed != nil, Date() < deadline { RunLoop.current.run(until: Date() + 0.01) }
        XCTAssertNil(removed)
    }
}
