import XCTest

final class AppInfoTests: XCTestCase {
    func testVersion() {
        XCTAssertEqual(AppInfo.version, "0.0.1")
    }
}
