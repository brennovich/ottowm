import XCTest

final class AXGeometryTests: XCTestCase {
    func testCGPointRoundTrip() {
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 100, y: 200),
            CGPoint(x: -50, y: 37.5),
            CGPoint(x: 1920, y: -1080),
        ]

        for point in points {
            XCTAssertEqual(decodeCGPoint(encodeCGPoint(point)), point)
        }
    }

    func testCGSizeRoundTrip() {
        let sizes = [
            CGSize(width: 0, height: 0),
            CGSize(width: 800, height: 600),
            CGSize(width: 1, height: 38),
            CGSize(width: 2560.5, height: 1440.25),
        ]

        for size in sizes {
            XCTAssertEqual(decodeCGSize(encodeCGSize(size)), size)
        }
    }

    func testDecodeRejectsMismatchedType() {
        let size = encodeCGSize(CGSize(width: 10, height: 20))

        XCTAssertNil(decodeCGPoint(size))
    }
}
