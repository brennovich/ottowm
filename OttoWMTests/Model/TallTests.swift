import CoreGraphics
import XCTest

final class TallTests: XCTestCase {
    private let bounds = CGRect(x: 10, y: 20, width: 400, height: 300)

    func testSlotsPutTheMainWindowBesideAStackColumnWithTheGapBetweenThem() {
        let cases: [(name: String, tall: Tall, slots: [CGRect])] = [
            ("one window", Tall(windowIds: [1], ratio: 0.5), [bounds]),
            ("equal stack", Tall(windowIds: [1, 2, 3], ratio: 0.5), [
                CGRect(x: 10, y: 20, width: 190, height: 300),
                CGRect(x: 220, y: 20, width: 190, height: 140),
                CGRect(x: 220, y: 180, width: 190, height: 140),
            ]),
            ("ratio", Tall(windowIds: [1, 2], ratio: 0.75), [
                CGRect(x: 10, y: 20, width: 285, height: 300),
                CGRect(x: 315, y: 20, width: 95, height: 300),
            ]),
            ("stack shares", Tall(windowIds: [1, 2, 3], ratio: 0.5, stackShares: [0.25, 0.75]), [
                CGRect(x: 10, y: 20, width: 190, height: 300),
                CGRect(x: 220, y: 20, width: 190, height: 70),
                CGRect(x: 220, y: 110, width: 190, height: 210),
            ]),
        ]

        for (name, tall, expected) in cases {
            XCTAssertEqual(tall.slots(within: bounds, gap: 20), expected, name)
        }
    }

    func testTheStackTakesTheOtherWindowsTopToBottomThenLeftToRight() {
        let others: [CGWindowID: CGRect] = [
            2: CGRect(x: 300, y: 200, width: 50, height: 50),
            3: CGRect(x: 0, y: 0, width: 50, height: 50),
            4: CGRect(x: 100, y: 0, width: 50, height: 50),
        ]

        XCTAssertEqual(Tall(main: 1, others: others).windowIds, [1, 3, 4, 2])
    }

    func testResizeMovesTheSharedEdge() {
        let tall = Tall(windowIds: [1, 2, 3], ratio: 0.5)
        let stack = { (shares: [CGFloat]) in Tall(windowIds: [1, 2, 3], ratio: 0.5, stackShares: shares) }

        let cases: [(name: String, windowId: CGWindowID, resize: Resize, result: Tall)] = [
            ("main wider", 1, Resize(change: .wider, points: 95), Tall(windowIds: [1, 2, 3], ratio: 0.75)),
            ("stack wider", 2, Resize(change: .wider, points: 95), Tall(windowIds: [1, 2, 3], ratio: 0.25)),
            ("stack taller takes from below", 2, Resize(change: .taller, points: 70), stack([0.75, 0.25])),
            ("bottom taller takes from above", 3, Resize(change: .taller, points: 70), stack([0.25, 0.75])),
            ("stack shorter gives below", 2, Resize(change: .shorter, points: 70), stack([0.25, 0.75])),
        ]

        for (name, windowId, resize, expected) in cases {
            XCTAssertEqual(tall.resizing(windowId, resize, within: bounds, gap: 20), expected, name)
        }
    }

    func testResizeIsDroppedWithoutAWindowOnTheOtherSideOfTheEdge() {
        let cases: [(name: String, tall: Tall, windowId: CGWindowID, change: Resize.Change)] = [
            ("main taller", Tall(windowIds: [1, 2, 3]), 1, .taller),
            ("single stack window taller", Tall(windowIds: [1, 2]), 2, .taller),
            ("one window wider", Tall(windowIds: [1]), 1, .wider),
            ("unknown window", Tall(windowIds: [1, 2]), 9, .wider),
        ]

        for (name, tall, windowId, change) in cases {
            XCTAssertNil(tall.resizing(windowId, Resize(change: change, points: 1), within: bounds, gap: 20), name)
        }
    }

    func testSwapTradesSlotsWithTheWindowTheDirectionLeadsTo() {
        let tall = Tall(windowIds: [1, 2, 3, 4], ratio: 0.5)

        let cases: [(name: String, windowId: CGWindowID, direction: Direction, windowIds: [CGWindowID]?)] = [
            ("stack west to main", 3, .west, [3, 2, 1, 4]),
            ("stack south", 2, .south, [1, 3, 2, 4]),
            ("main east to the top of the stack", 1, .east, [2, 1, 3, 4]),
            ("main west", 1, .west, nil),
            ("main north", 1, .north, nil),
            ("stack east", 2, .east, nil),
        ]

        for (name, windowId, direction, expected) in cases {
            XCTAssertEqual(tall.swapping(windowId, direction, within: bounds, gap: 20)?.windowIds, expected, name)
        }
    }

    func testMainGoingBackToTheStackTakesTheSlotItsWindowCameFrom() {
        let tall = Tall(windowIds: [1, 2, 3, 4], ratio: 0.5)

        let promoted = tall.swapping(4, .west, within: bounds, gap: 20)
        let demoted = promoted?.swapping(4, .east, within: bounds, gap: 20)

        XCTAssertEqual(demoted?.windowIds, [1, 2, 3, 4])
    }

    func testSwapKeepsTheShares() {
        let tall = Tall(windowIds: [1, 2, 3], ratio: 0.5, stackShares: [0.25, 0.75])

        XCTAssertEqual(tall.swapping(2, .south, within: bounds, gap: 20)?.stackShares, [0.25, 0.75])
    }

    func testFittingGivesEachWindowItsMinimumAndTheOthersTheRest() {
        let three = Tall(windowIds: [1, 2, 3], ratio: 0.5)
        let four = Tall(windowIds: [1, 2, 3, 4], ratio: 0.5)
        let height = { (height: CGFloat) in CGSize(width: 0, height: height) }
        let width = { (width: CGFloat) in CGSize(width: width, height: 0) }

        let cases: [(name: String, tall: Tall, minimums: [CGWindowID: CGSize], result: Tall?)] = [
            ("fits as it is", Tall(windowIds: [1, 2, 3], ratio: 0.71), [:], Tall(windowIds: [1, 2, 3], ratio: 0.71)),
            ("a stack height", three, [2: height(210)], Tall(windowIds: [1, 2, 3], ratio: 0.5, stackShares: [0.75, 0.25])),
            (
                "a height that pushes another below its own",
                four,
                [2: height(130), 3: height(78)],
                Tall(windowIds: [1, 2, 3, 4], ratio: 0.5, stackShares: [0.5, 0.3, 0.2])
            ),
            ("a stack width", three, [3: width(285)], Tall(windowIds: [1, 2, 3], ratio: 0.25)),
            ("a main width", three, [1: width(285)], Tall(windowIds: [1, 2, 3], ratio: 0.75)),
            ("heights over the column", three, [2: height(200), 3: height(200)], nil),
            ("a height leaving the others under the floor", three, [2: height(270)], nil),
            ("widths over the screen", three, [1: width(200), 2: width(200)], nil),
            ("a main height over the screen", three, [1: height(301)], nil),
        ]

        for (name, tall, minimums, expected) in cases {
            XCTAssertEqual(tall.fitted(to: minimums, within: bounds, gap: 20, floor: 20), expected, name)
        }
    }

    func testFitsWhenEverySlotHoldsTheMinimumOfItsWindowAndTheFloor() {
        let tall = Tall(windowIds: [1, 2, 3], ratio: 0.5)

        let cases: [(name: String, minimums: [CGWindowID: CGSize], floor: CGFloat, fits: Bool)] = [
            ("minimum held", [2: CGSize(width: 190, height: 140)], 140, true),
            ("stack height over", [3: CGSize(width: 0, height: 141)], 0, false),
            ("main width over", [1: CGSize(width: 191, height: 0)], 0, false),
            ("floor over", [:], 141, false),
        ]

        for (name, minimums, floor, expected) in cases {
            XCTAssertEqual(tall.fits(minimums, within: bounds, gap: 20, floor: floor), expected, name)
        }
    }
}
