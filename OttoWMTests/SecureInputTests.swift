import XCTest

final class SecureInputTests: XCTestCase {
    private func secureInput(set: Bool) -> SecureInput {
        SecureInput(lookUp: { { set } })
    }

    func testTheFlagIsReadThroughSkyLight() {
        XCTAssertNotNil(SecureInput().isSet())
    }

    func testAFlagSkyLightNoLongerExportsIsUnreadable() {
        XCTAssertNil(SecureInput(lookUp: { nil }).isSet())
    }

    func testASetFlagWarnsThatKeystrokesStopAtTheWindowServer() {
        XCTAssertEqual(
            secureInput(set: true).warning(),
            "secure event input is set by another app, no keystroke reaches the event tap"
        )
    }

    func testAClearFlagWarnsAboutNothing() {
        XCTAssertNil(secureInput(set: false).warning())
    }
}
