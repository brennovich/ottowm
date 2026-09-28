import ServiceManagement
import XCTest

final class LoginItemTests: XCTestCase {
    @available(macOS 13, *)
    func testTheStateFollowsTheServiceStatus() {
        let testCases: [(status: SMAppService.Status, state: LoginItem.State)] = [
            (.enabled, .on),
            (.requiresApproval, .needsApproval),
            (.notRegistered, .off),
            (.notFound, .off),
        ]

        for testCase in testCases {
            XCTAssertEqual(LoginItem.State(testCase.status), testCase.state, "\(testCase.status)")
        }
    }
}
