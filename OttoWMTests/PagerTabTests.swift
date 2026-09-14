import XCTest

final class PagerTabTests: XCTestCase {
    func testTheTabSitsInTheBottomRightCornerOfTheScreen() {
        let screenFrame = CGRect(x: 1792, y: -200, width: 2560, height: 1440)

        XCTAssertEqual(PagerTab.frame(in: screenFrame), CGRect(x: 4298, y: -200, width: 54, height: 58))
    }
}
