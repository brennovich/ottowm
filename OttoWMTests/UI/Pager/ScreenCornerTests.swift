import XCTest

final class ScreenCornerTests: XCTestCase {
    func testTheRadiusFollowsTheWindowCornersOfTheMacOSVersion() {
        let cases: [(majorVersion: Int, radius: CGFloat)] = [
            (15, 9),
            (26, 16),
        ]

        for testCase in cases {
            let version = OperatingSystemVersion(majorVersion: testCase.majorVersion, minorVersion: 0, patchVersion: 0)
            XCTAssertEqual(ScreenCorner.radius(on: version), testCase.radius, "macOS \(testCase.majorVersion)")
        }
    }

    func testEachCornerSitsInItsCornerOfTheScreen() {
        let screenFrame = CGRect(x: 1792, y: -200, width: 2560, height: 1440)

        let frames = ScreenCorner.allCases.map { $0.frame(in: screenFrame, radius: 16) }

        XCTAssertEqual(frames, [
            CGRect(x: 1792, y: 1224, width: 16, height: 16),
            CGRect(x: 4336, y: 1224, width: 16, height: 16),
            CGRect(x: 1792, y: -200, width: 16, height: 16),
        ])
    }

    func testTheMaskFillsOnlyTheScreenCornerOfItsSquare() {
        let points = [CGPoint(x: 1, y: 1), CGPoint(x: 15, y: 1), CGPoint(x: 1, y: 15), CGPoint(x: 15, y: 15)]
        let cases: [(corner: ScreenCorner, filled: CGPoint)] = [
            (.topLeft, CGPoint(x: 1, y: 1)),
            (.topRight, CGPoint(x: 15, y: 1)),
            (.bottomLeft, CGPoint(x: 1, y: 15)),
        ]

        for testCase in cases {
            let mask = testCase.corner.mask(radius: 16)

            XCTAssertEqual(points.filter { mask.contains($0) }, [testCase.filled], "\(testCase.corner)")
        }
    }

    func testTheMaskHidesPastItsScreenCorner() {
        let cases: [(corner: ScreenCorner, offset: CGSize)] = [
            (.topLeft, CGSize(width: -16, height: -16)),
            (.topRight, CGSize(width: 16, height: -16)),
            (.bottomLeft, CGSize(width: -16, height: 16)),
        ]

        for testCase in cases {
            XCTAssertEqual(testCase.corner.hiddenOffset(radius: 16), testCase.offset, "\(testCase.corner)")
        }
    }
}
