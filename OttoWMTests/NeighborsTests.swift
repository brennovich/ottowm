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

    func testNearestAlongTheAxisWinsAmongWindowsSharingRows() {
        let neighbors = Neighbors(around: reference, among: [
            100: CGRect(x: 1600, y: 450, width: 400, height: 200),
            200: CGRect(x: 1250, y: 350, width: 400, height: 200),
        ])

        XCTAssertEqual(neighbors.nearest(to: .east), 200)
    }

    func testEqualAxisDistanceFallsToTheNearestAcrossIt() {
        let neighbors = Neighbors(around: reference, among: [
            100: CGRect(x: 1400, y: 900, width: 200, height: 100),
            200: CGRect(x: 1400, y: 700, width: 200, height: 100),
        ])

        XCTAssertEqual(neighbors.nearest(to: .east), 200)
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

    func testWindowSharingTheReferenceCenterLiesInNoDirection() {
        let neighbors = Neighbors(around: reference, among: [100: reference])

        for direction in Direction.allCases {
            XCTAssertNil(neighbors.nearest(to: direction), direction.rawValue)
        }
    }

    func testNoWindowThatWay() {
        let neighbors = Neighbors(around: reference, among: [
            100: CGRect(x: 1300, y: 400, width: 400, height: 200),
        ])

        XCTAssertNil(neighbors.nearest(to: .west))
    }
}
