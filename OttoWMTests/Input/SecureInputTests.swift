import Carbon
import XCTest

final class SecureInputTests: XCTestCase {
    func testTheFlagFollowsSecureEventInput() {
        addTeardownBlock { DisableSecureEventInput() }

        EnableSecureEventInput()
        XCTAssertTrue(SecureInput().isActive())

        DisableSecureEventInput()
        XCTAssertFalse(SecureInput().isActive())
    }
}
