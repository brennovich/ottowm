import CoreGraphics
import XCTest

final class NeighborsTests: XCTestCase {
    private let reference = CGRect(x: 800, y: 400, width: 400, height: 200)

    func testNearestInEachDirection() {
        let neighbors = Neighbors(around: reference, among: [
            100: CGRect(x: 1300, y: 400, width: 400, height: 200),
            200: CGRect(x: 300, y: 400, width: 400, height: 200),
            300: CGRect(x: 800, y: 100, width: 400, height: 200),
            400: CGRect(x: 800, y: 700, width: 400, height: 200),
        ])

        let cases: [(name: String, direction: Direction, expected: CGWindowID)] = [
            ("east", .east, 100),
            ("west", .west, 200),
            ("north", .north, 300),
            ("south", .south, 400),
        ]

        for testCase in cases {
            XCTAssertEqual(neighbors.nearest(to: testCase.direction), testCase.expected, testCase.name)
        }
    }

    func testWindowSharingRowsWinsOverACloserOneThatDoesNot() {
        let neighbors = Neighbors(around: reference, among: [
            100: CGRect(x: 1250, y: 0, width: 400, height: 200),
            200: CGRect(x: 1600, y: 450, width: 400, height: 200),
        ])

        XCTAssertEqual(neighbors.nearest(to: .east), 200)
    }

    func testWindowSharingColumnsWinsOverACloserOneThatDoesNot() {
        let neighbors = Neighbors(around: reference, among: [
            100: CGRect(x: 0, y: 150, width: 400, height: 200),
            200: CGRect(x: 850, y: 0, width: 400, height: 200),
        ])

        XCTAssertEqual(neighbors.nearest(to: .north), 200)
    }

    func testWindowOnlyClippingTheLaneLosesToOneLinedUpWithIt() {
        let neighbors = Neighbors(around: reference, among: [
            100: CGRect(x: 1150, y: 700, width: 400, height: 190),
            200: CGRect(x: 800, y: 700, width: 400, height: 200),
        ])

        XCTAssertEqual(neighbors.nearest(to: .south), 200)
    }

    func testNearestEdgeAlongTheAxisWinsAmongWindowsSharingRows() {
        let neighbors = Neighbors(around: reference, among: [
            100: CGRect(x: 1300, y: 400, width: 200, height: 200),
            200: CGRect(x: 1250, y: 400, width: 400, height: 200),
        ])

        XCTAssertEqual(neighbors.nearest(to: .east), 200)
    }

    func testEqualEdgeDistanceFallsToTheTopmostOrLeftmost() {
        let cases: [(name: String, direction: Direction, candidates: [CGWindowID: CGRect], expected: CGWindowID)] = [
            ("east takes the topmost", .east, [
                100: CGRect(x: 1400, y: 200, width: 200, height: 300),
                200: CGRect(x: 1400, y: 480, width: 200, height: 100),
            ], 100),
            ("south takes the leftmost", .south, [
                100: CGRect(x: 500, y: 700, width: 600, height: 200),
                200: CGRect(x: 900, y: 700, width: 200, height: 200),
            ], 100),
        ]

        for testCase in cases {
            let neighbors = Neighbors(around: reference, among: testCase.candidates)

            XCTAssertEqual(neighbors.nearest(to: testCase.direction), testCase.expected, testCase.name)
        }
    }

    func testWindowsThatRankTheSameFallToTheLowestId() {
        let frame = CGRect(x: 1400, y: 900, width: 200, height: 100)
        let neighbors = Neighbors(around: reference, among: [300: frame, 100: frame, 200: frame])

        XCTAssertEqual(neighbors.nearest(to: .east), 100)
    }

    func testWindowCoveredByTheReferenceIsStillReachable() {
        let neighbors = Neighbors(around: reference, among: [
            100: CGRect(x: 810, y: 410, width: 100, height: 100),
        ])

        XCTAssertEqual(neighbors.nearest(to: .west), 100)
    }

    func testWindowSharingTheReferenceCenterIsReachableInEveryDirection() {
        let neighbors = Neighbors(around: reference, among: [100: reference])

        for direction in Direction.allCases {
            XCTAssertEqual(neighbors.nearest(to: direction), 100, direction.rawValue)
        }
    }

    func testWindowLyingInTheDirectionWinsOverOneSharingTheReferenceCenter() {
        let neighbors = Neighbors(around: reference, among: [
            100: reference,
            200: CGRect(x: 1600, y: 0, width: 400, height: 200),
        ])

        XCTAssertEqual(neighbors.nearest(to: .east), 200)
    }

    func testNoWindowThatWay() {
        let neighbors = Neighbors(around: reference, among: [
            100: CGRect(x: 1300, y: 400, width: 400, height: 200),
        ])

        XCTAssertNil(neighbors.nearest(to: .west))
    }
}
