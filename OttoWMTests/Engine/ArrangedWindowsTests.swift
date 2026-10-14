import CoreGraphics
import XCTest

final class ArrangedWindowsTests: EngineTestCase {
    private let top = CGRect(x: 100, y: 100, width: 400, height: 300)
    private let middle = CGRect(x: 100, y: 450, width: 400, height: 300)
    private let bottom = CGRect(x: 100, y: 800, width: 400, height: 200)

    private lazy var arranged = ArrangedWindows(
        desktop: desktop,
        windowSystem: windowSystem,
        workspaces: workspaces,
        placement: placement
    )

    private func slots(of windowIds: [CGWindowID]) -> [CGRect] {
        Tall(windowIds: windowIds).slots(within: desktop.workArea.filled, gap: desktop.workArea.spacing)
    }

    private func arrangeCalls(_ windowIds: [CGWindowID], _ slots: [CGRect]) -> [FrameRequest] {
        zip(windowIds, slots).map { FrameRequest(windowId: $0, change: .arrange(into: $1)) }
    }

    @discardableResult
    private func arrangeThree() -> (main: StubWindow, upper: StubWindow, lower: StubWindow) {
        let lower = create(StubWindow(id: 100, frame: bottom))
        let main = create(StubWindow(id: 200, frame: middle))
        let upper = create(StubWindow(id: 300, frame: top))
        desktop.clearCalls()
        arranged.arrange(around: main.snapshot())
        desktop.clearCalls()
        return (main, upper, lower)
    }

    func testArrangeSendsTheFocusedWindowToMainAndTheOthersToTheStackTopToBottom() {
        let lower = create(StubWindow(id: 100, frame: bottom))
        let main = create(StubWindow(id: 200, frame: middle))
        create(StubWindow(id: 300, frame: top))
        desktop.clearCalls()

        arranged.arrange(around: main.snapshot())

        XCTAssertEqual(desktop.reframeCalls, arrangeCalls([200, 300, 100], slots(of: [200, 300, 100])))
        XCTAssertEqual(workspaces.arranged(in: 1), Tall(windowIds: [200, 300, lower.id]))
    }

    func testWindowsNotOnScreenOrParkedAreLeftOut() {
        let main = create(StubWindow(id: 100, frame: top))
        create(StubWindow(id: 200, frame: middle))
        offScreenWindowIds = [200]
        let parked = create(StubWindow(id: 300, frame: bottom))
        parkedWindows.park(parked.id, from: bottom)
        desktop.clearCalls()

        arranged.arrange(around: main.snapshot())

        XCTAssertEqual(desktop.reframeCalls, arrangeCalls([100], [desktop.workArea.filled]))
    }

    func testArrangingAnIntactArrangementRestoresEveryWindowWhicheverIsFocused() {
        let (_, upper, _) = arrangeThree()

        arranged.arrange(around: upper.snapshot())

        XCTAssertEqual(desktop.reframeCalls, [
            FrameRequest(windowId: 200, change: .restore(middle)),
            FrameRequest(windowId: 300, change: .restore(top)),
            FrameRequest(windowId: 100, change: .restore(bottom)),
        ])
        XCTAssertNil(workspaces.arranged(in: 1))
    }

    func testArrangingABrokenArrangementArrangesTheWindowsAgain() {
        let (main, upper, lower) = arrangeThree()
        lower.moveTo(bottom)

        arranged.arrange(around: upper.snapshot())

        XCTAssertEqual(desktop.reframeCalls, arrangeCalls([300, 200, 100], slots(of: [upper.id, main.id, lower.id])))
    }

    func testATabShownInTheSlotOfItsSiblingHoldsTheArrangement() {
        let (tab1, tab2, other) = createFocusedTabPair()
        offScreenWindowIds = [tab1.id]
        desktop.clearCalls()
        arranged.arrange(around: other.snapshot())
        desktop.clearCalls()
        offScreenWindowIds = [tab2.id]
        tab1.moveTo(tab2.frame)

        arranged.arrange(around: other.snapshot())

        XCTAssertEqual(Set(desktop.reframeCalls.map(\.windowId)), [other.id, tab1.id])
        XCTAssertTrue(desktop.reframeCalls.allSatisfy { if case .restore = $0.change { true } else { false } })
    }

    func testResizeMovesTheSharedEdgeOfAnIntactArrangement() {
        let (main, _, _) = arrangeThree()
        let workArea = desktop.workArea
        let resized = Tall(windowIds: [200, 300, 100])
            .resizing(main.id, Resize(change: .wider, points: workArea.spacing), within: workArea.filled, gap: workArea.spacing)

        let slots = resized?.slots(within: workArea.filled, gap: workArea.spacing) ?? []

        XCTAssertTrue(arranged.resize(main.snapshot(), .wider))

        XCTAssertEqual(desktop.reframeCalls, arrangeCalls([200, 300, 100], slots))
        XCTAssertEqual(workspaces.arranged(in: 1), resized)
    }

    func testSwapMovesOnlyTheTwoWindowsTradingSlots() {
        let (_, upper, _) = arrangeThree()
        let slots = slots(of: [200, 300, 100])

        XCTAssertTrue(arranged.swap(upper.snapshot(), .south))

        XCTAssertEqual(desktop.reframeCalls, arrangeCalls([100, 300], [slots[1], slots[2]]))
    }

    func testSwapMovesTheColumnEdgeForTheMinimumWidthOfTheWindowGoingToMain() {
        create(StubWindow(id: 100, frame: bottom))
        let main = create(StubWindow(id: 200, frame: middle))
        let upper = create(StubWindow(id: 300, frame: top))
        upper.minimumSize = CGSize(width: 1200, height: 0)
        arranged.arrange(around: main.snapshot())

        XCTAssertTrue(arranged.swap(upper.snapshot(), .west))

        XCTAssertEqual(workspaces.arranged(in: 1)?.windowIds, [300, 200, 100])
    }

    func testAResizeAWindowRefusesIsUndone() {
        let (_, upper, lower) = arrangeThree()
        let slots = slots(of: [200, 300, 100])
        lower.minimumSize = slots[2].size

        XCTAssertTrue(arranged.resize(upper.snapshot(), .taller))

        XCTAssertEqual(upper.frame, slots[1])
        XCTAssertEqual(lower.frame, slots[2])
        XCTAssertEqual(workspaces.arranged(in: 1), Tall(windowIds: [200, 300, 100]))
    }

    func testArrangeGivesAWindowThatRefusesItsSlotItsSizeAndTheOthersTheRest() {
        let lower = create(StubWindow(id: 100, frame: CGRect(x: 100, y: 400, width: 400, height: 600)))
        let main = create(StubWindow(id: 200, frame: middle))
        let upper = create(StubWindow(id: 300, frame: top))
        lower.minimumSize = CGSize(width: 0, height: 600)
        let workArea = desktop.workArea
        let fitted = Tall(windowIds: [200, 300, 100])
            .fitted(to: [100: CGSize(width: 0, height: 600)], within: workArea.filled, gap: workArea.spacing, floor: 0)

        arranged.arrange(around: main.snapshot())

        let slots = fitted?.slots(within: workArea.filled, gap: workArea.spacing)
        XCTAssertEqual([main.frame, upper.frame, lower.frame], slots)
        XCTAssertEqual(workspaces.arranged(in: 1), fitted)
    }

    func testAWindowThatKeepsASizeShortOfItsSlotGoesBackAndTheOthersAreArranged() {
        let fixed = CGRect(x: 100, y: 50, width: 300, height: 1000)
        let lower = create(StubWindow(id: 100, frame: fixed))
        let main = create(StubWindow(id: 200, frame: middle))
        let upper = create(StubWindow(id: 300, frame: top))
        lower.minimumSize = fixed.size
        lower.maximumSize = fixed.size

        arranged.arrange(around: main.snapshot())

        XCTAssertEqual([main.frame, upper.frame, lower.frame], slots(of: [200, 300]) + [fixed])
        XCTAssertEqual(workspaces.arranged(in: 1), Tall(windowIds: [200, 300]))

        upper.moveTo(top)
        desktop.clearCalls()
        arranged.arrange(around: main.snapshot())
        XCTAssertFalse(desktop.reframeCalls.map(\.windowId).contains(lower.id), "the window is known to keep its size")
    }

    func testArrangeLeavesEveryWindowWhereItWasWhenTheFocusedWindowKeepsASizeSmallerThanItsSlot() {
        let lower = create(StubWindow(id: 100, frame: bottom))
        let main = create(StubWindow(id: 200, frame: middle))
        let upper = create(StubWindow(id: 300, frame: top))
        main.maximumSize = middle.size

        arranged.arrange(around: main.snapshot())

        XCTAssertEqual([main.frame, upper.frame, lower.frame], [middle, top, bottom])
        XCTAssertNil(workspaces.arranged(in: 1))

        desktop.clearCalls()
        arranged.arrange(around: main.snapshot())
        XCTAssertTrue(desktop.reframeCalls.isEmpty, "the window is known to keep its size")
    }

    func testAForgottenWindowLosesItsLearnedMinimumAndFixedSize() {
        let fixed = create(StubWindow(id: 100, frame: bottom))
        let main = create(StubWindow(id: 200, frame: middle))
        let wide = create(StubWindow(id: 300, frame: top))
        fixed.maximumSize = bottom.size
        wide.minimumSize = CGSize(width: 1200, height: 0)
        arranged.arrange(around: main.snapshot())
        fixed.maximumSize = CGSize(width: CGFloat.infinity, height: .infinity)
        wide.minimumSize = .zero
        wide.moveTo(top)
        desktop.clearCalls()

        arranged.forget(fixed.id)
        arranged.forget(wide.id)
        arranged.arrange(around: main.snapshot())

        XCTAssertEqual(desktop.reframeCalls, arrangeCalls([200, 300, 100], slots(of: [200, 300, 100])))
    }

    func testArrangeLeavesEveryWindowWhereItWasWhenTheMinimumsDoNotFit() {
        let tallTop = CGRect(x: 100, y: 0, width: 400, height: 600)
        let tallBottom = CGRect(x: 600, y: 400, width: 400, height: 600)
        let lower = create(StubWindow(id: 100, frame: tallBottom))
        let main = create(StubWindow(id: 200, frame: middle))
        let upper = create(StubWindow(id: 300, frame: tallTop))
        lower.minimumSize = tallBottom.size
        upper.minimumSize = tallTop.size

        arranged.arrange(around: main.snapshot())

        XCTAssertEqual([main.frame, upper.frame, lower.frame], [middle, tallTop, tallBottom])
        XCTAssertNil(workspaces.arranged(in: 1))

        desktop.clearCalls()
        arranged.arrange(around: main.snapshot())
        XCTAssertTrue(desktop.reframeCalls.isEmpty, "the minimums are known")
    }

    func testAResizeBelowALearnedMinimumMovesNothing() {
        let (_, upper, lower) = arrangeThree()
        lower.minimumSize = lower.frame.size
        arranged.resize(upper.snapshot(), .taller)
        desktop.clearCalls()

        XCTAssertTrue(arranged.resize(upper.snapshot(), .taller))

        XCTAssertTrue(desktop.reframeCalls.isEmpty)
    }

    func testAChangeTheArrangementRefusesIsDroppedRatherThanLeftToThePlainPath() {
        let main = create(StubWindow(id: 100, frame: top))
        arranged.arrange(around: main.snapshot())
        desktop.clearCalls()

        XCTAssertTrue(arranged.resize(main.snapshot(), .wider))
        XCTAssertTrue(desktop.reframeCalls.isEmpty)
    }

    func testAWindowOutsideAnIntactArrangementIsLeftToThePlainPath() {
        let (main, _, lower) = arrangeThree()
        let floating = create(StubWindow(id: 400, frame: top))
        desktop.clearCalls()

        XCTAssertFalse(arranged.resize(floating.snapshot(), .wider), "a window the arrangement does not hold")
        lower.moveTo(bottom)
        XCTAssertFalse(arranged.swap(main.snapshot(), .east), "a broken arrangement")
        XCTAssertTrue(desktop.reframeCalls.isEmpty)
    }

    func testAMaximizedWindowOfAnIntactArrangementGoesBackToItsSlot() {
        let (_, upper, _) = arrangeThree()
        upper.moveTo(desktop.workArea.filled)
        desktop.maximizedFrame = desktop.workArea.filled

        XCTAssertTrue(arranged.returnToSlot(upper.snapshot()))

        XCTAssertEqual(desktop.reframeCalls, arrangeCalls([300], [slots(of: [200, 300, 100])[1]]))
    }

    func testAMaximizedWindowOfABrokenArrangementIsLeftToMaximize() {
        let (_, upper, lower) = arrangeThree()
        upper.moveTo(desktop.workArea.filled)
        desktop.maximizedFrame = desktop.workArea.filled
        lower.moveTo(bottom)

        XCTAssertFalse(arranged.returnToSlot(upper.snapshot()))
    }

    func testTheWindowOfASingleWindowArrangementIsLeftToMaximize() {
        let single = create(StubWindow(id: 500, frame: top))
        arranged.arrange(around: single.snapshot())
        desktop.clearCalls()
        desktop.maximizedFrame = desktop.workArea.filled

        XCTAssertFalse(arranged.returnToSlot(single.snapshot()))
    }
}
