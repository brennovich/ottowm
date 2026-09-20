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

    func testWatchingReportsTheFlagAtOnce() {
        addTeardownBlock { DisableSecureEventInput() }
        var reports: [Bool] = []
        EnableSecureEventInput()

        SecureInput().startWatching { reports.append($0) }

        XCTAssertEqual(reports, [true])
    }
}
