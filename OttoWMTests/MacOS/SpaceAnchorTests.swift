import CoreGraphics
import XCTest

final class SpaceAnchorTests: XCTestCase {
    func testTheAnchorIsFramedAtTheTopLeftOfItsDisplayInAppKitCoordinates() {
        let aboveAndRight = Display(
            id: DisplayID(rawValue: "external"),
            fullFrame: CGRect(x: 1792, y: -320, width: 2560, height: 1440),
            visibleFrame: CGRect(x: 1792, y: -295, width: 2560, height: 1415)
        )

        XCTAssertEqual(
            SpaceAnchor.frame(on: aboveAndRight, primaryHeight: 1120),
            CGRect(x: 1792, y: 1439, width: 1, height: 1)
        )
    }
}
